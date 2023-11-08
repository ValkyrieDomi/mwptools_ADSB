package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"math"
	"net/http"
	"os"
	"strings"
)

type BingRes struct {
	ResourceSets []struct {
		Resources []struct {
			Elevations []int
			Zoomlevel  int
		}
	}
	Statuscode        int
	Statusdescription string
}

const ENCSTR string = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
const KENC string = "QXFzVEFpcGFCQnBLTFhoY2FHZ1A4a2NlWXVrYXRtdERMUzF4MENYRWhSWm5wbDFSRUxGOWhsSThqNG1OSWtyRQ=="

func pca(pts []Point) string {
	lat := int64(0)
	lon := int64(0)
	var sb strings.Builder

	for _, s := range pts {
		nlat := int64(math.Round(s.Y * 100000.0))
		nlon := int64(math.Round(s.X * 100000.0))
		dy := nlat - lat
		dx := nlon - lon
		lat = nlat
		lon = nlon

		dy = (dy << 1) ^ (dy >> 31)
		dx = (dx << 1) ^ (dx >> 31)
		index := ((dy + dx) * (dy + dx + 1) / 2) + dy
		rem := int64(0)
		for index > 0 {
			rem = index & 31
			index = (index - rem) / 32
			if index > 0 {
				rem += 32
			}
			sb.WriteByte(ENCSTR[rem])
		}
	}
	return sb.String()
}

func parse_response(js []byte) []int {
	var ev BingRes
	//	fmt.Fprintf(os.Stderr, "%s\n", string(js))
	json.Unmarshal(js, &ev)
	return ev.ResourceSets[0].Resources[0].Elevations
}

func Get_elevations(p []Point, nsamp int) ([]int, error) {
	var elev []int

	astr := os.Getenv("MWP_BING_KEY")
	if astr == "" {
		bs, _ := base64.StdEncoding.DecodeString(KENC)
		astr = string(bs)
	}
	var sb strings.Builder
	sb.WriteString("http://dev.virtualearth.net/REST/v1/Elevation/")
	if nsamp == 0 {
		sb.WriteString("List/")
	} else {
		sb.WriteString("Polyline/")
	}
	sb.WriteString("?key=")
	sb.WriteString(astr)
	if nsamp != 0 {
		sb.WriteString(fmt.Sprintf("&samp=%d", nsamp))
	}
	pstr := pca(p)
	pstr = fmt.Sprintf("points=%s", pstr)
	req, err := http.NewRequest("POST", sb.String(), bytes.NewBufferString(pstr))
	req.Header.Set("Accept", "*/*")
	req.Header.Set("Content-Type", "text/plain; charset=utf-8")
	req.Header.Set("Content-Length", fmt.Sprintf("%d", len(pstr)))

	client := &http.Client{}
	resp, err := client.Do(req)
	if err == nil {
		defer resp.Body.Close()
		body, err := ioutil.ReadAll(resp.Body)
		if err == nil && resp.StatusCode == 200 {
			elev = parse_response(body)
		}
	}
	return elev, err
}
