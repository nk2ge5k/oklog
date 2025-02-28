package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"time"

	"oklog/pkg/group"
	"oklog/pkg/store"

	"github.com/oklog/ulid"
	"github.com/pkg/errors"
)

func runStream(args []string) error {
	flagset := flag.NewFlagSet("stream", flag.ExitOnError)
	var (
		storeAddr = flagset.String(
			"store", "localhost:7650",
			"address of store instance to query")
		q = flagset.String(
			"q", "",
			"query expression")
		regex = flagset.Bool(
			"regex", false,
			"parse -q as regular expression")
		window = flagset.Duration(
			"window", 3*time.Second,
			"deduplication window")
		withulid = flagset.Bool(
			"ulid", false,
			"include ULID prefix with each record")
	)
	flagset.Usage = usageFor(flagset, "oklog stream [flags]")
	if err := flagset.Parse(args); err != nil {
		return err
	}

	_, hostport, _, _, err := parseAddr(*storeAddr, defaultAPIPort)
	if err != nil {
		return errors.Wrap(err, "couldn't parse -store")
	}

	var asRegex string
	if *regex {
		asRegex = "&regex=true"
	}

	var offset = ulid.EncodedSize + 1
	if *withulid {
		offset = 0
	}

	req, err := http.NewRequestWithContext(
		context.TODO(),
		"GET", fmt.Sprintf(
			"http://%s/store%s?q=%s&window=%s%s",
			hostport,
			store.APIPathUserStream,
			url.QueryEscape(*q),
			url.QueryEscape(window.String()),
			asRegex,
		), http.NoBody)
	if err != nil {
		return err
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	if resp.StatusCode != http.StatusOK {
		req.URL.RawQuery = "" // for pretty print
		return errors.Errorf("%s %s: %s", req.Method, req.URL.String(), resp.Status)
	}
	defer resp.Body.Close()

	var g group.Group
	{
		g.Add(func() error {
			scanner := bufio.NewScanner(resp.Body)
			for scanner.Scan() {
				fmt.Fprintf(os.Stdout, "%s\n", scanner.Bytes()[offset:])
			}
			return scanner.Err()
		}, func(error) {
			resp.Body.Close()
		})
	}
	{
		cancel := make(chan struct{})
		g.Add(func() error {
			return interrupt(cancel)
		}, func(error) {
			close(cancel)
		})
	}
	return g.Run()
}
