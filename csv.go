package main

import (
	"encoding/csv"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"time"
)

type Summary struct {
	Serial         string
	Days           map[string]struct{}
	DownloadSpeeds []float64
	UploadSpeeds   []float64
}

func main() {
	// Open input CSV
	inputFile, err := os.Open("marco_ke_Y4_ka_14.csv")
	if err != nil {
		log.Fatal(err)
	}
	defer inputFile.Close()

	reader := csv.NewReader(inputFile)
	reader.FieldsPerRecord = -1

	records, err := reader.ReadAll()
	if err != nil {
		log.Fatal(err)
	}

	if len(records) < 1 {
		log.Fatal("CSV has no data")
	}

	// Map serial -> summary
	summaries := make(map[string]*Summary)

	for i, row := range records {
		if i == 0 {
			continue // skip header
		}

		serial := row[0]

		// Parse date part of timestamp
		t, err := time.Parse("2006-01-02 15:04:05.000 -0700", row[3])
		if err != nil {
			// fallback if fractional seconds differ
			ts := strings.Split(row[3], ".")[0]
			t, _ = time.Parse("2006-01-02 15:04:05", ts)
		}
		day := t.Format("2006-01-02")

		downloadSpeed, _ := strconv.ParseFloat(row[7], 64)
		uploadSpeed, _ := strconv.ParseFloat(row[8], 64)

		if _, exists := summaries[serial]; !exists {
			summaries[serial] = &Summary{
				Serial:         serial,
				Days:           make(map[string]struct{}),
				DownloadSpeeds: []float64{},
				UploadSpeeds:   []float64{},
			}
		}

		s := summaries[serial]
		s.Days[day] = struct{}{}
		s.DownloadSpeeds = append(s.DownloadSpeeds, downloadSpeed)
		s.UploadSpeeds = append(s.UploadSpeeds, uploadSpeed)
	}

	// Write output CSV
	outputFile, err := os.Create("output.csv")
	if err != nil {
		log.Fatal(err)
	}
	defer outputFile.Close()

	writer := csv.NewWriter(outputFile)
	defer writer.Flush()

	// Write header
	writer.Write([]string{"Serial", "Days", "AvgDownloadSpeed(Mbps)", "AvgUploadSpeed(Mbps)"})

	for _, s := range summaries {
		avgDownload := average(s.DownloadSpeeds)
		avgUpload := average(s.UploadSpeeds)
		writer.Write([]string{
			s.Serial,
			strconv.Itoa(len(s.Days)),
			fmt.Sprintf("%.3f", avgDownload),
			fmt.Sprintf("%.3f", avgUpload),
		})
	}

	fmt.Println("Done! Output written to output.csv")
}

func average(nums []float64) float64 {
	if len(nums) == 0 {
		return 0
	}
	var sum float64
	for _, n := range nums {
		sum += n
	}
	return sum / float64(len(nums))
}
