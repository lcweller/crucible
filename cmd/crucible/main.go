// SPDX-License-Identifier: BUSL-1.1
//
// Copyright (c) 2026 The Crucible Authors
//
// Use of this source code is governed by the Business Source License 1.1
// included in the LICENSE file at the root of this repository. On
// 2030-05-13, this file will become available under the Apache License,
// Version 2.0, in accordance with the Change License clause of the BSL.
//
// Production use is permitted, including commercial use, subject to the
// Additional Use Grant in LICENSING.md, which prohibits offering Crucible
// itself as a hosted or managed service to third parties before the
// Change Date.

// Crucible - ephemeral, cross-platform workload fingerprinting and
// hardware recommendation CLI. Phase 0 scaffold only; commands are
// stubs that will be filled in subsequent phases.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/crucible-io/crucible/internal/cli"
)

// Build-time variables populated via -ldflags in the Makefile / CI.
var (
	version = "dev"
	commit  = "none"
	date    = "unknown"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(),
		os.Interrupt, syscall.SIGTERM)
	defer cancel()

	root := cli.NewRootCommand(cli.BuildInfo{
		Version: version,
		Commit:  commit,
		Date:    date,
	})

	if err := root.ExecuteContext(ctx); err != nil {
		slog.Error("command failed", "err", err)
		fmt.Fprintln(os.Stderr, "crucible:", err)
		os.Exit(1)
	}
}
