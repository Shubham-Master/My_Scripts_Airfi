package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
)

const (
	queueURL  = "https://sqs.eu-west-1.amazonaws.com/649763982056/log-processing-queue"
	boxFile   = "/home/ubuntu/logs-processing/boxIps.txt"
	region    = "eu-west-1"
	maxBatch  = 10 // SQS limit
	maxWorker = 50 // concurrent workers
)

type Payload struct {
	BoxID     string `json:"boxId"`
	StartDate string `json:"startDate"`
	EndDate   string `json:"endDate"`
}

func splitIntoQuarters(start, end time.Time) [][2]string {
	var result [][2]string
	cur := start
	for cur.Before(end) || cur.Equal(end) {
		next := cur.AddDate(0, 3, -1)
		if next.After(end) {
			next = end
		}
		result = append(result, [2]string{
			cur.Format("2006-01-02"),
			next.Format("2006-01-02"),
		})
		cur = next.AddDate(0, 0, 1)
	}
	return result
}

func main() {
	ctx := context.Background()

	if len(os.Args) < 3 {
		log.Fatalf("Usage: %s <startDate YYYY-MM-DD> <endDate YYYY-MM-DD>", os.Args[0])
	}
	startArg := os.Args[1]
	endArg := os.Args[2]
	tStart, err := time.Parse("2006-01-02", startArg)
	if err != nil {
		log.Fatalf("invalid start date %q: %v", startArg, err)
	}
	tEnd, err := time.Parse("2006-01-02", endArg)
	if err != nil {
		log.Fatalf("invalid end date %q: %v", endArg, err)
	}
	if tStart.After(tEnd) {
		log.Fatalf("startDate must be <= endDate (got %s > %s)", startArg, endArg)
	}
	startDate := tStart.Format("2006-01-02")
	endDate := tEnd.Format("2006-01-02")

	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		log.Fatalf("failed to load AWS config: %v", err)
	}

	client := sqs.NewFromConfig(cfg)

	boxes, err := readBoxIDs(boxFile)
	if err != nil {
		log.Fatalf("failed to read box IDs: %v", err)
	}

	log.Printf("📦 Sending jobs for range %s → %s (%d boxes)", startDate, endDate, len(boxes))

	jobs := make(chan []Payload, len(boxes))
	wg := sync.WaitGroup{}

	// Worker pool
	for w := 0; w < maxWorker; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for batch := range jobs {
				sendBatch(ctx, client, batch)
			}
		}()
	}

	// Prepare messages in batches of 10
	current := []Payload{}
	for _, box := range boxes {
		for _, rng := range splitIntoQuarters(tStart, tEnd) {
			current = append(current, Payload{
				BoxID:     box,
				StartDate: rng[0],
				EndDate:   rng[1],
			})
			if len(current) == maxBatch {
				jobs <- current
				current = []Payload{}
			}
		}
	}
	if len(current) > 0 {
		jobs <- current
	}
	close(jobs)

	wg.Wait()
	log.Println("✅ All messages sent successfully.")
}

// readBoxIDs reads each non-empty line as a box ID
func readBoxIDs(path string) ([]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var boxes []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if line != "" {
			boxes = append(boxes, line)
		}
	}
	return boxes, scanner.Err()
}

// sendBatch sends up to 10 messages in one SQS batch request
func sendBatch(ctx context.Context, client *sqs.Client, payloads []Payload) {
	entries := make([]types.SendMessageBatchRequestEntry, 0, len(payloads))
	for _, p := range payloads {
		body, _ := json.Marshal(p)
		safeID := strings.ReplaceAll(p.BoxID, ".", "_")
		entryID := fmt.Sprintf("%s_%s_%s", safeID, p.StartDate, p.EndDate)
		if len(entryID) > 80 {
			entryID = entryID[:80]
		}
		entries = append(entries, types.SendMessageBatchRequestEntry{
			Id:          aws.String(entryID),
			MessageBody: aws.String(string(body)),
		})
	}

	input := &sqs.SendMessageBatchInput{
		QueueUrl: aws.String(queueURL),
		Entries:  entries,
	}

	out, err := client.SendMessageBatch(ctx, input)
	if err != nil {
		log.Printf("❌ batch send error: %v", err)
		for _, p := range payloads {
			log.Printf("   ↳ [FAILED] Box=%s Range=%s→%s", p.BoxID, p.StartDate, p.EndDate)
		}
		return
	}

	// Log successful and failed messages in detail
	for _, success := range out.Successful {
		log.Printf("✅ [SENT] %s (SQS MessageID=%s)", *success.Id, *success.MessageId)
	}
	for _, fail := range out.Failed {
		log.Printf("❌ [FAILED] %s (%s)", *fail.Id, *fail.Message)
	}

	log.Printf("🚀 Batch summary: %d sent, %d failed", len(out.Successful), len(out.Failed))
}
