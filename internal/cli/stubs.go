package cli

import (
	"errors"

	"github.com/spf13/cobra"
)

// errNotImplemented is returned by every Phase 0 stub. Each subcommand
// will be implemented in its dedicated phase per CLAUDE.md.
var errNotImplemented = errors.New("not implemented in Phase 0 — see CLAUDE.md phase plan")

func newDoctorCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "doctor",
		Short: "Pre-flight: kernel, eBPF, PMU, GPU drivers, permissions",
		Long:  "Reports exactly what Crucible can and cannot measure on this host before a real run.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return errNotImplemented
		},
	}
}

func newRunCommand() *cobra.Command {
	c := &cobra.Command{
		Use:   "run",
		Short: "Observe the workload for a window and emit a report",
		RunE: func(cmd *cobra.Command, args []string) error {
			return errNotImplemented
		},
	}
	c.Flags().Duration("window", 0, "Observation window (e.g. 1h, 24h, 7d). Default 24h.")
	c.Flags().String("output", "", "Output directory for report artifacts")
	c.Flags().String("upload-url", "", "Optional HTTPS endpoint to POST report.json + report.pdf")
	c.Flags().String("upload-token", "", "Bearer token for --upload-url")
	c.Flags().String("email-to", "", "Optional email recipient for PDF report")
	c.Flags().String("smtp-config", "", "SMTP relay config file")
	c.Flags().Bool("keep-raw", false, "Preserve raw sample database after run")
	c.Flags().Bool("snapshot", false, "60s 1Hz snapshot mode instead of a full window")
	return c
}

func newStatusCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Show progress of a running session",
		RunE: func(cmd *cobra.Command, args []string) error {
			return errNotImplemented
		},
	}
}

func newReportCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "report",
		Short: "Re-render artifacts from a completed run",
		RunE: func(cmd *cobra.Command, args []string) error {
			return errNotImplemented
		},
	}
}

func newUninstallCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "uninstall",
		Short: "Remove the binary, temp data, systemd units, and logs — leave no trace",
		RunE: func(cmd *cobra.Command, args []string) error {
			return errNotImplemented
		},
	}
}
