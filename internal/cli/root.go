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

// Package cli wires up the root Cobra command and all subcommands.
// Phase 0: command stubs only. Real implementations land in later phases.
package cli

import (
	"github.com/spf13/cobra"
)

// BuildInfo carries -ldflags-injected build metadata into the CLI.
type BuildInfo struct {
	Version string
	Commit  string
	Date    string
}

// NewRootCommand constructs the root `crucible` command and registers
// all subcommands.
func NewRootCommand(b BuildInfo) *cobra.Command {
	root := &cobra.Command{
		Use:           "crucible",
		Short:         "Ephemeral, cross-platform workload fingerprinting and hardware recommendation",
		Long:          longDescription,
		SilenceUsage:  true,
		SilenceErrors: true,
	}

	root.AddCommand(newVersionCommand(b))
	root.AddCommand(newDoctorCommand())
	root.AddCommand(newRunCommand())
	root.AddCommand(newStatusCommand())
	root.AddCommand(newReportCommand())
	root.AddCommand(newUninstallCommand())

	return root
}

const longDescription = `Crucible observes a live production workload, fingerprints its
resource behavior across CPU, memory, storage, network, and GPU, and
produces a vendor-neutral hardware recommendation describing the
characteristics of a server that would run the same workload better.

Crucible runs ephemerally, leaves no trace on uninstall, and never
calls out to an LLM at runtime.`
