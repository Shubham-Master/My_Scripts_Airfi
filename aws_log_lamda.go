package main

import (
	"bufio"
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// Buckets
const (
	srcBucket = "airserver-backups"
	dstBucket = "airserver-logs-processed"
)

// SQS message schema
type LogJob struct {
	BoxID     string `json:"boxId"`     // e.g., "10.0.10.101"
	StartDate string `json:"startDate"` // "MMYYYY"
	EndDate   string `json:"endDate"`   // "MMYYYY"
}

// parse "MMYYYY" to time.Time at month start (UTC)
func parseMMYYYY(val string) (time.Time, error) {
	return time.Parse("012006", val)
}

func handler(ctx context.Context, sqsEvent events.SQSEvent) error {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("aws config error: %v", err)
	}
	s3Client := s3.NewFromConfig(cfg)

	for _, record := range sqsEvent.Records {
		var job LogJob
		if err := json.Unmarshal([]byte(record.Body), &job); err != nil {
			log.Printf("❌ invalid SQS message: %v", err)
			continue
		}
		if job.BoxID == "" || job.StartDate == "" || job.EndDate == "" {
			log.Printf("❌ missing fields in message: %+v", job)
			continue
		}

		if err := processBox(ctx, s3Client, job); err != nil {
			log.Printf("❌ failed box %s: %v", job.BoxID, err)
			// (Optionally) return err to requeue; keeping continue avoids poison-loop
		}
	}
	return nil
}

func processBox(ctx context.Context, s3c *s3.Client, job LogJob) error {
	start, err := parseMMYYYY(job.StartDate)
	if err != nil {
		return fmt.Errorf("invalid startDate %q: %w", job.StartDate, err)
	}
	end, err := parseMMYYYY(job.EndDate)
	if err != nil {
		return fmt.Errorf("invalid endDate %q: %w", job.EndDate, err)
	}
	// end is exclusive: add one month
	end = end.AddDate(0, 1, 0)

	prefix := fmt.Sprintf("logs/%s/", job.BoxID)
	log.Printf("📦 Box=%s  Range=%s→%s  Prefix=%s", job.BoxID, job.StartDate, job.EndDate, prefix)

	// exact Bash parity regex (zgrep -E pattern)
	reKeep := regexp.MustCompile(`airfi-cmd\.sh --list: IATA=|init: (SWver|HWver|HWrev|powman-ver|Box power-(up|down))|STM32\[BQ24620\[status=|STC3115\[chg=|airfi-cmd\.sh: --(shutdown|reboot)`)
	reKernelInit := regexp.MustCompile(`kernel: .*init:`)
	reSTM32Line := regexp.MustCompile(`^[0-9TZ:+-]+.* 10-.* STM32`)
	reBQ24620 := regexp.MustCompile(`BQ24620\[status=([0-9]+)[^S]*STC3115`)

	pager := s3.NewListObjectsV2Paginator(s3c, &s3.ListObjectsV2Input{
		Bucket: aws.String(srcBucket),
		Prefix: aws.String(prefix),
	})

	for pager.HasMorePages() {
		page, err := pager.NextPage(ctx)
		if err != nil {
			return fmt.Errorf("list-objects failed: %w", err)
		}
		for _, obj := range page.Contents {
			// date window filter on LastModified
			if obj.LastModified.Before(start) || !obj.LastModified.Before(end) {
				continue
			}

			key := aws.ToString(obj.Key)
			// only maintenance gz logs
			if !strings.Contains(key, "logfile-maintenance-") || !strings.HasSuffix(key, ".gz") {
				continue
			}

			// storage class check (STANDARD or GLACIER_IR only)
			head, err := s3c.HeadObject(ctx, &s3.HeadObjectInput{
				Bucket: aws.String(srcBucket),
				Key:    aws.String(key),
			})
			if err != nil {
				log.Printf("[%s] ⚠️ head-object %s failed: %v", job.BoxID, key, err)
				continue
			}
			storageClass := "STANDARD"
			if head.StorageClass != "" {
				storageClass = string(head.StorageClass)
			}
			if storageClass != "STANDARD" && storageClass != "GLACIER_IR" {
				log.Printf("[%s] ⏭️ skip %s (storageClass=%s)", job.BoxID, key, storageClass)
				continue
			}

			year := obj.LastModified.Format("2006")
			parts := strings.Split(key, "/")
			filename := filepath.Base(strings.TrimSuffix(parts[len(parts)-1], ".gz")) + "_STM_LOG.txt"
			outKey := fmt.Sprintf("log/%s/%s/%s", year, job.BoxID, filename)

			// Check if output file already exists
			_, err = s3c.HeadObject(ctx, &s3.HeadObjectInput{
				Bucket: aws.String(dstBucket),
				Key:    aws.String(outKey),
			})
			if err == nil {
				log.Printf("[%s] ⏭️ skipped already processed %s", job.BoxID, outKey)
				continue
			}

			// download
			objOut, err := s3c.GetObject(ctx, &s3.GetObjectInput{
				Bucket: aws.String(srcBucket),
				Key:    aws.String(key),
			})
			if err != nil {
				log.Printf("[%s] ⚠️ get-object %s failed: %v", job.BoxID, key, err)
				continue
			}

			gzr, err := gzip.NewReader(objOut.Body)
			if err != nil {
				log.Printf("[%s] ❌ gzip reader error for %s: %v", job.BoxID, key, err)
				_ = objOut.Body.Close()
				continue
			}

			// Process the file in one pass to mirror Bash (and avoid double downloads)
			sc := bufio.NewScanner(gzr)
			// (Optionally) increase buffer for very long log lines
			const maxLine = 1024 * 1024
			buf := make([]byte, 0, 64*1024)
			sc.Buffer(buf, maxLine)

			seen := make(map[string]struct{})
			var outLines []string // lines except IATA
			var iataLine string   // last IATA= line stored for printing at the end
			foundFASE := false
			foundLTC := false

			for sc.Scan() {
				line := sc.Text()

				// Skip conditions (Bash parity):
				// - FASE='on' anywhere -> skip file
				if strings.Contains(line, "airfi-cmd.sh --list: FASE='on'") {
					foundFASE = true
					break
				}
				// - LTC4156 anywhere (matches your Bash grep -m1 "LTC4156")
				if strings.Contains(line, "LTC4156") {
					foundLTC = true
					break
				}

				// zgrep filter
				if !reKeep.MatchString(line) {
					continue
				}
				// exclude sensors and kernel init
				if strings.Contains(line, "/usr/bin/sensors") || reKernelInit.MatchString(line) {
					continue
				}

				// sed-like transforms on STM32 lines
				if reSTM32Line.MatchString(line) {
					// remove "/usr/bin/powman[...]: " prefix if present
					// emulate: s#/usr/bin/powman\[.*\]:[[:space:]]*## on those lines
					if idx := strings.Index(line, "/usr/bin/powman"); idx != -1 {
						// remove from the powman prefix start up to the following ": " (if present)
						rest := line[idx:]
						colon := strings.Index(rest, ":")
						if colon != -1 {
							// cut that segment
							line = line[:idx] + strings.TrimLeft(rest[colon+1:], " \t")
						}
					}
					// merge BQ24620 status with STC3115
					line = reBQ24620.ReplaceAllString(line, "BQ24620[status=$1 STC3115")
				}

				// IATA re-ordering: keep the last IATA= line and print it at the end (awk parity)
				if strings.Contains(line, "IATA=") {
					iataLine = line
					continue
				}

				// de-duplicate
				if _, ok := seen[line]; !ok {
					outLines = append(outLines, line)
					seen[line] = struct{}{}
				}
			}
			_ = gzr.Close()
			_ = objOut.Body.Close()

			if foundFASE {
				log.Printf("[%s] ⛔ skipped (FASE='on') %s", job.BoxID, key)
				continue
			}
			if foundLTC {
				log.Printf("[%s] ⛔ skipped (LTC4156) %s", job.BoxID, key)
				continue
			}

			// append IATA last if present (awk END block)
			if iataLine != "" {
				if _, ok := seen[iataLine]; !ok {
					outLines = append(outLines, iataLine)
				}
			}

			// nothing to write?
			if len(outLines) == 0 {
				log.Printf("[%s] (empty STM extract) %s", job.BoxID, key)
				continue
			}

			// build output content
			var outBuf bytes.Buffer
			for _, l := range outLines {
				outBuf.WriteString(l)
				outBuf.WriteByte('\n')
			}

			// destination key: log/<YEAR>/<BOX_ID>/<filename>_STM_LOG.txt
			// year, parts, filename, and outKey already initialized above

			_, err = s3c.PutObject(ctx, &s3.PutObjectInput{
				Bucket: aws.String(dstBucket),
				Key:    aws.String(outKey),
				Body:   bytes.NewReader(outBuf.Bytes()),
			})
			if err != nil {
				log.Printf("[%s] ❌ upload failed %s: %v", job.BoxID, outKey, err)
				continue
			}
			log.Printf("[%s] ✅ uploaded s3://%s/%s", job.BoxID, dstBucket, outKey)
		}
	}

	return nil
}

func main() {
	lambda.Start(handler)
}
