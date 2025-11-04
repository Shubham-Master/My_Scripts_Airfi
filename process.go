package main

import (
	"bufio"
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// Buckets
const (
	srcBucket = "airserver-backups"
	dstBucket = "airserver-logs-processed"
)

// MongoDB configuration
const (
	databaseName         = "airserver_logs"
	mongoInsertBatchSize = 1000
)

type LogEntry struct {
	Time        time.Time `bson:"time"`
	BoxIP       string    `bson:"boxIP"`
	ServiceName string    `bson:"serviceName"`
	LogLine     string    `bson:"logLine"`
	LogFileName string    `bson:"logFileName"`
	ProcessedAt time.Time `bson:"processedAt"`
}

// SQS message schema
type LogJob struct {
	BoxID     string `json:"boxId"`     // e.g., "10.0.10.101"
	StartDate string `json:"startDate"` // "MMYYYY", "2025-10-01", "2025-10-01T00:00:00Z"
	EndDate   string `json:"endDate"`   // "MMYYYY", "2025-10-21", "2025-10-21T23:59:59Z"
}

// parse date string to time.Time
// Supports formats: "MMYYYY", "2025-10-01", "2025-10-01T00:00:00Z"
func parseDate(val string) (time.Time, error) {
	// Try different date formats
	formats := []string{
		"012006",                   // MMYYYY
		"2006-01-02",               // YYYY-MM-DD
		"2006-01-02T15:04:05Z",     // ISO 8601
		"2006-01-02T15:04:05.000Z", // ISO 8601 with milliseconds
	}

	for _, format := range formats {
		if t, err := time.Parse(format, val); err == nil {
			return t, nil
		}
	}
	return time.Time{}, fmt.Errorf("unable to parse date: %s", val)
}

func handler(ctx context.Context, sqsEvent events.SQSEvent) error {
	// Get MongoDB URI from environment variable
	mongoURI := getMongoURI()

	// Connect to MongoDB
	mongoClient, err := mongo.Connect(ctx, options.Client().ApplyURI(mongoURI))
	if err != nil {
		return fmt.Errorf("MongoDB connection error: %v", err)
	}
	defer mongoClient.Disconnect(ctx)

	// AWS S3 client for reading source files
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

		if err := processBox(ctx, s3Client, mongoClient, job); err != nil {
			log.Printf("❌ failed box %s: %v", job.BoxID, err)
			// (Optionally) return err to requeue; keeping continue avoids poison-loop
		}
	}

	return nil
}

func getMongoURI() string {
	// Check environment variable first
	if uri := os.Getenv("MONGO_URI"); uri != "" {
		return uri
	}
	// Default URI
	return "mongodb://localhost:27017"
}

func processBox(ctx context.Context, s3c *s3.Client, mongoClient *mongo.Client, job LogJob) error {
	start, err := parseDate(job.StartDate)
	if err != nil {
		return fmt.Errorf("invalid startDate %q: %w", job.StartDate, err)
	}

	end, err := parseDate(job.EndDate)
	if err != nil {
		return fmt.Errorf("invalid endDate %q: %w", job.EndDate, err)
	}

	// For date ranges, end is inclusive, so add 1 day to make it exclusive
	end = end.AddDate(0, 0, 1)

	prefix := fmt.Sprintf("logs/%s/", job.BoxID)
	log.Printf("📦 Box=%s Range=%s→%s Prefix=%s", job.BoxID, job.StartDate, job.EndDate, prefix)

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

			// process any logfile- gz files (both airfi and maintenance)
			if !strings.Contains(key, "logfile-") || !strings.HasSuffix(key, ".gz") {
				continue
			}

			// Enhanced storage class check: handle Deep Archive restore status
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

			// Check for Deep Archive objects with restore information
			restoreHeader := ""
			if head.Restore != nil {
				restoreHeader = *head.Restore
			}

			if storageClass == "DEEP_ARCHIVE" {
				if strings.Contains(restoreHeader, "ongoing-request=\"true\"") {
					log.Printf("[%s] ⏳ %s is still being restored (ongoing-request=true), skipping for now", job.BoxID, key)
					continue
				} else if strings.Contains(restoreHeader, "ongoing-request=\"false\"") {
					log.Printf("[%s] ✅ %s is restored and available for processing", job.BoxID, key)
					// proceed to process restored Deep Archive object
				} else {
					log.Printf("[%s] ⏭️ %s is DEEP_ARCHIVE and not yet requested for restore", job.BoxID, key)
					continue
				}
			} else if storageClass != "STANDARD" && storageClass != "GLACIER_IR" {
				log.Printf("[%s] ⏭️ skip %s (storageClass=%s)", job.BoxID, key, storageClass)
				continue
			}

			// Determine type (airfi or maintenance) by sampling first 10 current readings
			objHead, err := s3c.GetObject(ctx, &s3.GetObjectInput{
				Bucket: aws.String(srcBucket),
				Key:    aws.String(key),
			})
			if err != nil {
				log.Printf("[%s] ⚠️ failed to read header of %s: %v", job.BoxID, key, err)
				continue
			}

			gzrSample, err := gzip.NewReader(objHead.Body)
			if err != nil {
				log.Printf("[%s] ❌ gzip sample reader error for %s: %v", job.BoxID, key, err)
				_ = objHead.Body.Close()
				continue
			}

			scSample := bufio.NewScanner(gzrSample)
			positiveCount := 0
			negativeCount := 0
			totalChecked := 0
			currentRegex := regexp.MustCompile(`cur=\s*(-?\d+)\s*mA`)

			for scSample.Scan() {
				line := scSample.Text()
				matches := currentRegex.FindStringSubmatch(line)
				if len(matches) > 1 {
					val := matches[1]
					if strings.HasPrefix(val, "-") {
						negativeCount++
					} else {
						positiveCount++
					}
					totalChecked++
				}
				if totalChecked >= 10 {
					break
				}
			}

			_ = gzrSample.Close()
			_ = objHead.Body.Close()

			logType := "maintenance"
			if negativeCount > positiveCount {
				logType = "airfi"
			}

			log.Printf("[%s] 📊 classified %s as logfile-%s (neg=%d, pos=%d)", job.BoxID, key, logType, negativeCount, positiveCount)

			// Adjust filename and S3 path based on classification
			year := obj.LastModified.Format("2006")
			parts := strings.Split(key, "/")
			baseName := strings.TrimSuffix(filepath.Base(parts[len(parts)-1]), ".gz")

			// Build filename according to classification or source if inconclusive
			filename := ""
			if positiveCount == negativeCount {
				// Inconclusive: use original filename pattern from airserver-backups but replace .gz with _STM_LOG.txt
				filename = fmt.Sprintf("%s_STM_LOG.txt", baseName)
				log.Printf("[%s] ⚖️ inconclusive classification for %s, using original filename", job.BoxID, key)
			} else {
				// Remove any existing airfi/maintenance prefix to avoid duplication
				cleanedBase := strings.TrimPrefix(baseName, "logfile-airfi-")
				cleanedBase = strings.TrimPrefix(cleanedBase, "logfile-maintenance-")
				cleanedBase = strings.TrimPrefix(cleanedBase, "logfile-")
				if logType == "airfi" {
					filename = fmt.Sprintf("logfile-airfi-%s-STM_LOG.txt", cleanedBase)
				} else {
					filename = fmt.Sprintf("logfile-maintenance-%s-STM_LOG.txt", cleanedBase)
				}
			}

			// Use new S3 hierarchy: airserver-logs-processed/logs/year/boxid/
			outKey := fmt.Sprintf("logs/%s/%s/%s", year, job.BoxID, filename)

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
			foundLTC := false

			for sc.Scan() {
				line := sc.Text()

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

			// Insert processed log lines into MongoDB
			if len(outLines) > 0 {
				// Get MongoDB database and collection
				db := mongoClient.Database(databaseName)
				collectionName := fmt.Sprintf("log-%s", job.BoxID)
				collection := db.Collection(collectionName)

				// Create collection if it doesn't exist
				createCollectionIfNotExists(ctx, db, collectionName)

				// Parse and insert each log line
				var logEntries []interface{}
				processedAt := time.Now()
				totalProcessed := 0
				totalDuplicates := 0

				for _, line := range outLines {
					entry, err := parseLogLine(line, filename, key)
					if err != nil {
						log.Printf("[%s] ⚠️ error parsing line: %v", job.BoxID, err)
						continue
					}
					entry.ProcessedAt = processedAt
					logEntries = append(logEntries, entry)

					// Insert in batches
					if len(logEntries) >= mongoInsertBatchSize {
						inserted, duplicates := insertBatchWithDuplicateHandling(ctx, collection, logEntries, job.BoxID)
						totalProcessed += inserted
						totalDuplicates += duplicates
						logEntries = logEntries[:0] // Reset slice
					}
				}

				// Insert remaining entries
				if len(logEntries) > 0 {
					inserted, duplicates := insertBatchWithDuplicateHandling(ctx, collection, logEntries, job.BoxID)
					totalProcessed += inserted
					totalDuplicates += duplicates
				}

				log.Printf("[%s] ✅ processed %d log lines into MongoDB collection %s (%d inserted, %d duplicates skipped)",
					job.BoxID, len(outLines), collectionName, totalProcessed, totalDuplicates)

				// Upload processed STM log to S3
				outBuf := []byte(strings.Join(outLines, "\n") + "\n")
				_, err = s3c.PutObject(ctx, &s3.PutObjectInput{
					Bucket: aws.String(dstBucket),
					Key:    aws.String(outKey),
					Body:   bytes.NewReader(outBuf),
				})
				if err != nil {
					log.Printf("[%s] ❌ failed to upload processed log to S3: %v", job.BoxID, err)
				} else {
					log.Printf("[%s] ✅ uploaded processed log to s3://%s/%s", job.BoxID, dstBucket, outKey)
				}
			}
		}
	}

	return nil
}

func insertBatchWithDuplicateHandling(ctx context.Context, collection *mongo.Collection, logEntries []interface{}, boxID string) (inserted int, duplicates int) {
	if len(logEntries) == 0 {
		return 0, 0
	}

	// Use unordered inserts to continue on duplicate key errors
	opts := options.InsertMany().SetOrdered(false)

	result, err := collection.InsertMany(ctx, logEntries, opts)

	if err != nil {
		// Check if it's a bulk write exception (which includes duplicate key errors)
		if mongo.IsDuplicateKeyError(err) || strings.Contains(err.Error(), "E11000") {
			// Parse the bulk write exception to get actual insert count
			inserted = 0
			if result != nil {
				inserted = len(result.InsertedIDs)
			}
			duplicates = len(logEntries) - inserted

			log.Printf("[%s] ⏭️ batch: %d inserted, %d duplicates skipped", boxID, inserted, duplicates)
			return inserted, duplicates
		}

		// For other errors, log and return
		log.Printf("[%s] ❌ MongoDB batch insert failed: %v", boxID, err)
		return 0, 0
	}

	// All documents inserted successfully
	inserted = len(logEntries)
	log.Printf("[%s] ✅ inserted batch of %d entries", boxID, inserted)
	return inserted, 0
}

func createCollectionIfNotExists(ctx context.Context, db *mongo.Database, collectionName string) {
	// Check if collection exists
	collections, err := db.ListCollectionNames(ctx, bson.M{"name": collectionName})
	if err != nil {
		log.Printf("⚠️ failed to list collections: %v", err)
		return
	}

	// If collection doesn't exist, create it
	exists := false
	for _, name := range collections {
		if name == collectionName {
			exists = true
			break
		}
	}

	if !exists {
		opts := options.CreateCollection()
		opts.SetCapped(false)
		err = db.CreateCollection(ctx, collectionName, opts)
		if err != nil {
			log.Printf("⚠️ failed to create collection %s: %v", collectionName, err)
		} else {
			log.Printf("✅ created collection: %s", collectionName)
			// Get the collection reference and create indexes
			collection := db.Collection(collectionName)
			createIndexes(ctx, collection)
		}
	}
}

func createIndexes(ctx context.Context, collection *mongo.Collection) {
	// Create index on time field for better query performance
	timeIndex := mongo.IndexModel{
		Keys:    bson.D{{"time", 1}},
		Options: options.Index().SetName("time_1"),
	}

	// Create index on serviceName for filtering
	serviceIndex := mongo.IndexModel{
		Keys:    bson.D{{"serviceName", 1}},
		Options: options.Index().SetName("serviceName_1"),
	}

	// Create compound index on time and serviceName
	compoundIndex := mongo.IndexModel{
		Keys:    bson.D{{"time", 1}, {"serviceName", 1}},
		Options: options.Index().SetName("time_serviceName_1"),
	}

	// Unique index to prevent duplicates
	uniqueIndex := mongo.IndexModel{
		Keys: bson.D{
			{"time", 1},
			{"serviceName", 1},
			{"logLine", 1},
		},
		Options: options.Index().
			SetName("time_serviceName_logLine_unique").
			SetUnique(true),
	}

	_, err := collection.Indexes().CreateMany(ctx, []mongo.IndexModel{
		uniqueIndex,
		timeIndex,
		serviceIndex,
		compoundIndex,
	})
	if err != nil {
		log.Printf("⚠️ failed to create indexes: %v", err)
	} else {
		log.Printf("✅ created indexes for collection: %s", collection.Name())
	}
}

func parseLogLine(line, fileName, key string) (LogEntry, error) {
	// Split by first two spaces to separate timestamp, IP, and the rest
	parts := strings.SplitN(line, " ", 3)
	if len(parts) < 3 {
		return LogEntry{}, fmt.Errorf("invalid log format")
	}

	// Parse timestamp
	timestamp, err := time.Parse(time.RFC3339Nano, parts[0])
	if err != nil {
		return LogEntry{}, fmt.Errorf("invalid timestamp: %v", err)
	}

	// Extract service name and clean log line
	remaining := parts[2]
	serviceName := extractServiceName(remaining)

	// Clean the log line by removing the service name prefix
	cleanLogLine := cleanLogLineContent(remaining, serviceName)

	return LogEntry{
		Time:        timestamp,
		BoxIP:       parts[1],
		ServiceName: serviceName,
		LogLine:     cleanLogLine,
		LogFileName: key,
	}, nil
}

func extractServiceName(logLine string) string {
	// Look for common service patterns
	if strings.Contains(logLine, "init:") {
		return "init"
	}
	if strings.Contains(logLine, "STM32[") {
		return "STM32"
	}
	if strings.Contains(logLine, "airfi-cmd.sh") {
		return "airfi-cmd.sh"
	}
	if strings.Contains(logLine, "powman-ver:") {
		return "powman"
	}

	// Try to extract service name from the beginning of the log line
	// Look for pattern like "service: message" or "service message"
	colonIndex := strings.Index(logLine, ":")
	if colonIndex > 0 && colonIndex < 50 { // Reasonable service name length
		potentialService := strings.TrimSpace(logLine[:colonIndex])
		if len(potentialService) > 0 && len(potentialService) < 50 {
			return potentialService
		}
	}

	// Default fallback
	return "unknown"
}

func cleanLogLineContent(logLine, serviceName string) string {
	// Remove service name prefix from the log line to avoid duplication
	if serviceName == "init" {
		// Remove "init: " prefix
		if strings.HasPrefix(logLine, "init: ") {
			return strings.TrimSpace(logLine[6:])
		}
	} else if serviceName == "STM32" {
		// For STM32, the service name is already part of the content, so keep as is
		return logLine
	} else if serviceName == "airfi-cmd.sh" {
		// Remove "airfi-cmd.sh " prefix
		if strings.HasPrefix(logLine, "airfi-cmd.sh ") {
			return strings.TrimSpace(logLine[13:])
		}
	} else if serviceName == "powman" {
		// Remove "powman-ver: " prefix
		if strings.HasPrefix(logLine, "powman-ver: ") {
			return strings.TrimSpace(logLine[12:])
		}
	} else if serviceName != "unknown" {
		// For other services, try to remove the service name prefix
		servicePrefix := serviceName + ": "
		if strings.HasPrefix(logLine, servicePrefix) {
			return strings.TrimSpace(logLine[len(servicePrefix):])
		}
	}

	// If no service prefix found, return the original line
	return logLine
}

func main() {
	lambda.Start(handler)
}
