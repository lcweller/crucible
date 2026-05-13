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
