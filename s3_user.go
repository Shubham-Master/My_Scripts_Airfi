package main

import (
	"bufio"
	"bytes"
	"compress/gzip"
	"context"
	"fmt"
	"log"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// Buckets
const (
	srcBucket = "airserver-backups"
	dstBucket = "airserver-logs-processed"
)

// parse "MMYYYY" to time.Time
func parseMMYYYY(val string) (time.Time, error) {
	return time.Parse("012006", val)
}

func main() {
	var boxID, startStr, endStr string
	fmt.Print("Enter Box ID (e.g. 10.0.10.101): ")
	fmt.Scanln(&boxID)
	fmt.Print("Enter Start Date (MMYYYY): ")
	fmt.Scanln(&startStr)
	fmt.Print("Enter End Date (MMYYYY): ")
	fmt.Scanln(&endStr)

	start, err := parseMMYYYY(startStr)
	if err != nil {
		log.Fatalf("Invalid start date: %v", err)
	}
	end, err := parseMMYYYY(endStr)
	if err != nil {
		log.Fatalf("Invalid end date: %v", err)
	}
	end = end.AddDate(0, 1, 0)

	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		log.Fatalf("AWS config error: %v", err)
	}
	s3c := s3.NewFromConfig(cfg)
	processBox(context.TODO(), s3c, boxID, start, end)
}

func processBox(ctx context.Context, s3c *s3.Client, boxID string, start, end time.Time) {
	prefix := fmt.Sprintf("logs/%s/", boxID)
	log.Printf("📦 Box=%s  Range=%s→%s  Prefix=%s", boxID, start.Format("Jan 2006"), end.Format("Jan 2006"), prefix)

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
			log.Printf("ListObjects failed: %v", err)
			break
		}

		for _, obj := range page.Contents {
			if obj.LastModified.Before(start) || !obj.LastModified.Before(end) {
				continue
			}

			key := aws.ToString(obj.Key)
			if !strings.Contains(key, "logfile-maintenance-") || !strings.HasSuffix(key, ".gz") {
				continue
			}

			// storage class check
			head, err := s3c.HeadObject(ctx, &s3.HeadObjectInput{
				Bucket: aws.String(srcBucket),
				Key:    aws.String(key),
			})
			if err != nil {
				log.Printf("[%s] ⚠️ head-object failed: %v", boxID, err)
				continue
			}
			storageClass := "STANDARD"
			if head.StorageClass != "" {
				storageClass = string(head.StorageClass)
			}
			if storageClass != "STANDARD" && storageClass != "GLACIER_IR" {
				log.Printf("[%s] ⏭️ skip %s (storageClass=%s)", boxID, key, storageClass)
				continue
			}

			year := obj.LastModified.Format("2006")
			parts := strings.Split(key, "/")
			filename := filepath.Base(strings.TrimSuffix(parts[len(parts)-1], ".gz")) + "_STM_LOG.txt"
			outKey := fmt.Sprintf("log/%s/%s/%s", year, boxID, filename)

			// already processed check
			_, err = s3c.HeadObject(ctx, &s3.HeadObjectInput{
				Bucket: aws.String(dstBucket),
				Key:    aws.String(outKey),
			})
			if err == nil {
				log.Printf("[%s] ✅ already processed %s", boxID, outKey)
				continue
			}

			// download
			objOut, err := s3c.GetObject(ctx, &s3.GetObjectInput{
				Bucket: aws.String(srcBucket),
				Key:    aws.String(key),
			})
			if err != nil {
				log.Printf("[%s] ⚠️ get-object failed: %v", boxID, err)
				continue
			}

			gzr, err := gzip.NewReader(objOut.Body)
			if err != nil {
				log.Printf("[%s] ❌ gzip read error: %v", boxID, err)
				objOut.Body.Close()
				continue
			}

			sc := bufio.NewScanner(gzr)
			const maxLine = 1024 * 1024
			buf := make([]byte, 0, 64*1024)
			sc.Buffer(buf, maxLine)

			seen := make(map[string]struct{})
			var outLines []string
			var iataLine string
			foundFASE := false
			foundLTC := false

			for sc.Scan() {
				line := sc.Text()
				if strings.Contains(line, "airfi-cmd.sh --list: FASE='on'") {
					foundFASE = true
					break
				}
				if strings.Contains(line, "LTC4156") {
					foundLTC = true
					break
				}
				if !reKeep.MatchString(line) {
					continue
				}
				if strings.Contains(line, "/usr/bin/sensors") || reKernelInit.MatchString(line) {
					continue
				}

				if reSTM32Line.MatchString(line) {
					if idx := strings.Index(line, "/usr/bin/powman"); idx != -1 {
						rest := line[idx:]
						colon := strings.Index(rest, ":")
						if colon != -1 {
							line = line[:idx] + strings.TrimLeft(rest[colon+1:], " \t")
						}
					}
					line = reBQ24620.ReplaceAllString(line, "BQ24620[status=$1 STC3115")
				}

				if strings.Contains(line, "IATA=") {
					iataLine = line
					continue
				}
				if _, ok := seen[line]; !ok {
					outLines = append(outLines, line)
					seen[line] = struct{}{}
				}
			}
			gzr.Close()
			objOut.Body.Close()

			if foundFASE {
				log.Printf("[%s] ⛔ skip (FASE='on') %s", boxID, key)
				continue
			}
			if foundLTC {
				log.Printf("[%s] ⛔ skip (LTC4156) %s", boxID, key)
				continue
			}

			if iataLine != "" {
				if _, ok := seen[iataLine]; !ok {
					outLines = append(outLines, iataLine)
				}
			}
			if len(outLines) == 0 {
				log.Printf("[%s] (empty STM) %s", boxID, key)
				continue
			}

			var outBuf bytes.Buffer
			for _, l := range outLines {
				outBuf.WriteString(l)
				outBuf.WriteByte('\n')
			}

			_, err = s3c.PutObject(ctx, &s3.PutObjectInput{
				Bucket: aws.String(dstBucket),
				Key:    aws.String(outKey),
				Body:   bytes.NewReader(outBuf.Bytes()),
			})
			if err != nil {
				log.Printf("[%s] ❌ upload failed %s: %v", boxID, outKey, err)
				continue
			}
			log.Printf("[%s] ✅ uploaded s3://%s/%s", boxID, dstBucket, outKey)
		}
	}
}
