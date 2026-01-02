package main

import (
	"bufio"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const (
	baseDir   = "/logs"
	cutoffStr = "2025-12-30"
)

var (
	iataRegex         = regexp.MustCompile(`IATA='([^']+)'`)
	logStartDateRegex = regexp.MustCompile(`logfile-airfi-(\d{8})_`)
	successRegex      = regexp.MustCompile(`Date range.* and is valid`)

	allowedIATA = map[string]bool{
		"2D":  true,
		"9G":  true,
		"9P":  true,
		"AX":  true,
		"BNL": true,
		"CY":  true,
		"E5":  true,
		"EY":  true,
		"FJ":  true,
		"G9":  true,
		"HM":  true,
		"MRA": true,
		"NT":  true,
		"OY":  true,
		"PU":  true,
		"PY":  true,
		"RC":  true,
		"SY":  true,
		"W2":  true,
		"Y4":  true,
		"YU":  true,
	}
)

type Result struct {
	Box      string
	IATA     string
	LastSeen string
}

func main() {

	cutoff, err := time.Parse("2006-01-02", cutoffStr)
	if err != nil {
		panic(err)
	}

	fmt.Println("box,IATA,last_seen")

	boxes, err := os.ReadDir(baseDir)
	if err != nil {
		panic(err)
	}

	for _, box := range boxes {
		if !box.IsDir() || !strings.HasPrefix(box.Name(), "10.0.") {
			continue
		}

		boxPath := filepath.Join(baseDir, box.Name())

		var logs []string
		lastSeen := ""
		found := false
		iata := "UNKNOWN"
		skipBox := false

		filepath.WalkDir(boxPath, func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return nil
			}

			m := logStartDateRegex.FindStringSubmatch(d.Name())
			if len(m) != 2 {
				return nil
			}

			logDate, err := time.Parse("20060102", m[1])
			if err != nil || logDate.Before(cutoff) {
				return nil
			}

			logs = append(logs, path)

			if m[1] > lastSeen {
				lastSeen = m[1]
			}

			return nil
		})

		for _, logPath := range logs {
			ok, foundIATA := scanLog(logPath)

			if foundIATA != "UNKNOWN" {
				iata = foundIATA
				if !allowedIATA[iata] {
					skipBox = true
					break
				}
			}

			if ok {
				found = true
				break
			}
		}

		if !skipBox && !found && len(logs) > 0 {
			fmt.Printf("%s,%s,%s\n", box.Name(), iata, lastSeen)
		}
	}
}

func scanLog(path string) (bool, string) {
	file, err := os.Open(path)
	if err != nil {
		return false, "UNKNOWN"
	}
	defer file.Close()

	var reader io.Reader = file

	if strings.HasSuffix(path, ".gz") {
		gz, err := gzip.NewReader(file)
		if err != nil {
			return false, "UNKNOWN"
		}
		defer gz.Close()
		reader = gz
	}

	scanner := bufio.NewScanner(reader)
	buf := make([]byte, 0, 1024*1024)
	scanner.Buffer(buf, 10*1024*1024)

	iata := "UNKNOWN"

	for scanner.Scan() {
		line := scanner.Text()

		if iata == "UNKNOWN" {
			if m := iataRegex.FindStringSubmatch(line); len(m) == 2 {
				iata = m[1]
			}
		}

		if successRegex.MatchString(line) {
			return true, iata
		}
	}

	return false, iata
}
