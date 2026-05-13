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

package cli

import (
	"fmt"

	"github.com/spf13/cobra"
)

func newVersionCommand(b BuildInfo) *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print version, commit, and build date",
		RunE: func(cmd *cobra.Command, args []string) error {
			_, err := fmt.Fprintf(cmd.OutOrStdout(),
				"crucible %s (commit %s, built %s)\n",
				b.Version, b.Commit, b.Date)
			return err
		},
	}
}
