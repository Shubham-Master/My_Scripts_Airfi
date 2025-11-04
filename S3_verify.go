package main

import (
	"bufio"
	"context"
	"encoding/csv"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

const (
	bucket      = "airserver-backups"
	region      = "eu-west-1"
	processed   = "/home/ubuntu/processed_objects.txt"
	restoredCSV = "/home/ubuntu/restored_objects.csv"
	notRestored = "/home/ubuntu/notrestored.txt"
	maxWorkers  = 200
)

type result struct {
	Key        string
	Restored   bool
	ExpiryDate string
	InProgress bool
}

func worker(ctx context.Context, wg *sync.WaitGroup, svc *s3.Client, jobs <-chan string, results chan<- result) {
	defer wg.Done()
	for key := range jobs {
		input := &s3.HeadObjectInput{
			Bucket: aws.String(bucket),
			Key:    aws.String(key),
		}

		resp, err := svc.HeadObject(ctx, input)
		if err != nil {
			results <- result{Key: key}
			continue
		}

		// Check restore status from metadata
		restoreHeader := aws.ToString(resp.Restore)
		if restoreHeader == "" {
			results <- result{Key: key}
			continue
		}

		// Possible states: ongoing-request="true" or "false"
		if strings.Contains(restoreHeader, "ongoing-request=\"true\"") {
			results <- result{Key: key, InProgress: true}
		} else if strings.Contains(restoreHeader, "ongoing-request=\"false\"") {
			expiry := ""
			if idx := strings.Index(restoreHeader, "expiry-date=\""); idx != -1 {
				rest := restoreHeader[idx+13:]
				end := strings.Index(rest, "\"")
				if end != -1 {
					rawDate := rest[:end]

					// Parse and format expiry date
					layout := "Mon, 02 Jan 2006 15:04:05 MST"
					if t, err := time.Parse(layout, rawDate); err == nil {
						expiry = t.Format("02 Jan 2006")
					} else {
						expiry = rawDate // fallback if parsing fails
					}
				}
			}
			results <- result{Key: key, Restored: true, ExpiryDate: expiry}
		} else {
			results <- result{Key: key}
		}
	}
}

func main() {
	ctx := context.Background()

	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		fmt.Println("Failed to load AWS config:", err)
		return
	}
	svc := s3.NewFromConfig(cfg)

	file, err := os.Open(processed)
	if err != nil {
		fmt.Println("Error opening processed file:", err)
		return
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	jobs := make(chan string, 1000)
	results := make(chan result, 1000)

	var wg sync.WaitGroup
	for i := 0; i < maxWorkers; i++ {
		wg.Add(1)
		go worker(ctx, &wg, svc, jobs, results)
	}

	// Feed jobs
	go func() {
		for scanner.Scan() {
			key := strings.TrimSpace(scanner.Text())
			if key != "" {
				jobs <- key
			}
		}
		close(jobs)
	}()

	go func() {
		wg.Wait()
		close(results)
	}()

	restoredFile, _ := os.Create(restoredCSV)
	csvWriter := csv.NewWriter(restoredFile)
	csvWriter.Write([]string{"Key", "ExpiryDate"})

	notRestoredFile, _ := os.Create(notRestored)
	defer notRestoredFile.Close()

	var restoredCount, ongoingCount, failedCount int

	for res := range results {
		if res.Restored {
			csvWriter.Write([]string{res.Key, res.ExpiryDate})
			restoredCount++
		} else if res.InProgress {
			ongoingCount++
		} else {
			notRestoredFile.WriteString(res.Key + "\n")
			failedCount++
		}
	}

	csvWriter.Flush()
	restoredFile.Close()

	fmt.Printf("✅ Completed verification:\n")
	fmt.Printf("• Restored: %d\n", restoredCount)
	fmt.Printf("• In Progress: %d\n", ongoingCount)
	fmt.Printf("• Not Restored: %d\n", failedCount)
	fmt.Printf("Results saved to:\n%s and %s\n", restoredCSV, notRestored)
}
