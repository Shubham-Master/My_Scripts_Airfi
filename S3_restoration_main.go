package main

import (
    "bufio"
    "context"
    "fmt"
    "os"
    "strings"
    "sync"
    "sync/atomic"
    "time"
    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/service/s3"
    "github.com/aws/aws-sdk-go-v2/service/s3/types"
)

const (
    bucket         = "airserver-backups"
    daysToKeep     = 60
    maxWorkers     = 200
    inputFile      = "/home/ubuntu/logs_only.txt"
    processedFile  = "/home/ubuntu/processed_objects.txt"
    unprocessedFile= "/home/ubuntu/unprocessed.txt"
)

func worker(ctx context.Context, wg *sync.WaitGroup, keys <-chan string, client *s3.Client, results chan<- string) {
    defer wg.Done()
    var count int64
    for key := range keys {
        fmt.Printf("[%s] Attempting: %s\n", time.Now().Format("15:04:05"), key)
        input := &s3.RestoreObjectInput{
            Bucket: aws.String(bucket),
            Key:    aws.String(key),
            RestoreRequest: &types.RestoreRequest{
                Days: aws.Int32(daysToKeep),
                GlacierJobParameters: &types.GlacierJobParameters{
                    Tier: types.TierBulk,
                },
            },
        }
        _, err := client.RestoreObject(ctx, input)
        if err == nil || (err != nil && (strings.Contains(err.Error(), "RestoreAlreadyInProgress") || strings.Contains(err.Error(), "already restored"))) {
            fmt.Printf("[%s] ✅ Success: %s\n", time.Now().Format("15:04:05"), key)
            results <- key
            newCount := atomic.AddInt64(&count, 1)
            if newCount%1000 == 0 {
                fmt.Printf("[%s] Processed so far: %d objects\n", time.Now().Format("15:04:05"), newCount)
            }
        } else {
            fmt.Printf("[%s] 🔴 Failed: %s - %v\n", time.Now().Format("15:04:05"), key, err)
			sleep 60
        }
    }
}

func main() {
    // Read processed keys into a set
    processedKeys := make(map[string]bool)
    pf, err := os.Open(processedFile)
    if err == nil {
        scanner := bufio.NewScanner(pf)
        for scanner.Scan() {
            processedKeys[scanner.Text()] = true
        }
        pf.Close()
    }

    // Open inputFile and unprocessedFile for writing unprocessed keys
    inFile, err := os.Open(inputFile)
    if err != nil {
        fmt.Println("Error opening input file:", err)
        return
    }
    defer inFile.Close()

    outFile, err := os.OpenFile(unprocessedFile, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0644)
    if err != nil {
        fmt.Println("Error opening unprocessed file:", err)
        return
    }
    defer outFile.Close()

    scanner := bufio.NewScanner(inFile)
    for scanner.Scan() {
        key := scanner.Text()
        if !processedKeys[key] {
            fmt.Fprintln(outFile, key)
        }
    }

    // Now open unprocessedFile for reading keys to process
    unprocessedInFile, err := os.Open(unprocessedFile)
    if err != nil {
        fmt.Println("Error opening unprocessed file for reading:", err)
        return
    }
    defer unprocessedInFile.Close()

    cfg, err := config.LoadDefaultConfig(context.TODO(),
        config.WithRegion("eu-west-1"),
    )
    if err != nil {
        fmt.Println("Error loading AWS config:", err)
        return
    }
    client := s3.NewFromConfig(cfg)

    keys := make(chan string, 1000)
    results := make(chan string, 1000)

    var wg sync.WaitGroup
    for i := 0; i < maxWorkers; i++ {
        wg.Add(1)
        go worker(context.TODO(), &wg, keys, client, results)
    }

    go func() {
        wg.Wait()
        close(results)
    }()

    go func() {
        var lines []string
        scanner := bufio.NewScanner(unprocessedInFile)
        for scanner.Scan() {
            lines = append(lines, scanner.Text())
        }
        for i := len(lines) - 1; i >= 0; i-- {
            keys <- lines[i]
        }
        close(keys)
    }()

    out, _ := os.OpenFile(processedFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
    defer out.Close()

    for key := range results {
        fmt.Fprintln(out, key)
    }

    fmt.Println("✅ Restore requests queued successfully at", time.Now())
}

