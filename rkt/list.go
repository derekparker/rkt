// Copyright 2015 The rkt Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//+build linux

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/coreos/rkt/Godeps/_workspace/src/github.com/appc/spec/schema"
	"github.com/coreos/rkt/Godeps/_workspace/src/github.com/appc/spec/schema/lastditch"
	"github.com/coreos/rkt/Godeps/_workspace/src/github.com/spf13/cobra"
	common "github.com/coreos/rkt/common"
	"github.com/coreos/rkt/networking/netinfo"
	"github.com/coreos/rkt/store"
)

var (
	cmdList = &cobra.Command{
		Use:   "list",
		Short: "List pods",
		Run:   runWrapper(runList),
	}
	flagNoLegend   bool
	flagFullOutput bool
)

func init() {
	cmdRkt.AddCommand(cmdList)
	cmdList.Flags().BoolVar(&flagNoLegend, "no-legend", false, "suppress a legend with the list")
	cmdList.Flags().BoolVar(&flagFullOutput, "full", false, "use long output format")
}

func runList(cmd *cobra.Command, args []string) int {
	s, err := store.NewStore(globalFlags.Dir)
	if err != nil {
		stderr("list: cannot open store: %v", err)
		return 1
	}

	var errors []error
	tabBuffer := new(bytes.Buffer)
	tabOut := getTabOutWithWriter(tabBuffer)

	if !flagNoLegend {
		if flagFullOutput {
			fmt.Fprintf(tabOut, "UUID\tAPP\tIMAGE NAME\tIMAGE ID\tSTATE\tNETWORKS\n")
		} else {
			fmt.Fprintf(tabOut, "UUID\tAPP\tIMAGE NAME\tSTATE\tNETWORKS\n")
		}
	}

	if err := walkPods(includeMostDirs, func(p *pod) {
		pm := schema.PodManifest{}

		if !p.isPreparing && !p.isAbortedPrepare && !p.isExitedDeleting {
			// TODO(vc): we should really hold a shared lock here to prevent gc of the pod
			pmf, err := p.readFile(common.PodManifestPath(""))
			if err != nil {
				errors = append(errors, newPodListReadError(p, err))
				return
			}

			if err := pm.UnmarshalJSON(pmf); err != nil {
				errors = append(errors, newPodListLoadError(p, err, pmf))
				return
			}

			if len(pm.Apps) == 0 {
				errors = append(errors, newPodListZeroAppsError(p))
				return
			}
		}

		type printedApp struct {
			uuid    string
			appName string
			imgName string
			imgID   string
			state   string
			nets    string
		}

		var appsToPrint []printedApp
		uuid := p.uuid.String()
		state := p.getState()
		nets := fmtNets(p.nets)
		if !flagFullOutput {
			uuid = uuid[:8]
		}
		for _, app := range pm.Apps {
			// Retrieve the image from the store.
			imj, err := s.GetImageManifestJSON(app.Image.ID.String())
			if err != nil {
				errors = append(errors, newPodListImageStoreFailure(p, err, &pm, app))
				return
			}
			var im *schema.ImageManifest
			if err = json.Unmarshal(imj, &im); err != nil {
				errors = append(errors, newPodListImageLoadFailure(p, err, &pm, imj, app))
				return
			}

			imageName := im.Name.String()
			if version, ok := im.Labels.Get("version"); ok {
				imageName = fmt.Sprintf("%s:%s", imageName, version)
			}

			var imageID string
			if flagFullOutput {
				imageID = app.Image.ID.String()[:19]
			}

			appsToPrint = append(appsToPrint, printedApp{
				uuid:    uuid,
				appName: app.Name.String(),
				imgName: imageName,
				imgID:   imageID,
				state:   state,
				nets:    nets,
			})
			// clear those variables so they won't be
			// printed for another apps in the pod as they
			// are actually describing a pod, not an app
			uuid = ""
			state = ""
			nets = ""
		}
		// if we reached that point, then it means that the
		// pod and all its apps are valid, so they can be
		// printed
		for _, app := range appsToPrint {
			if flagFullOutput {
				fmt.Fprintf(tabOut, "%s\t%s\t%s\t%s\t%s\t%s\n", app.uuid, app.appName, app.imgName, app.imgID, app.state, app.nets)
			} else {
				fmt.Fprintf(tabOut, "%s\t%s\t%s\t%s\t%s\n", app.uuid, app.appName, app.imgName, app.state, app.nets)
			}
		}

	}); err != nil {
		stderr("Failed to get pod handles: %v", err)
		return 1
	}

	if len(errors) > 0 {
		sep := "----------------------------------------"
		stderr("%d error(s) encountered when listing pods:", len(errors))
		stderr("%s", sep)
		for _, err := range errors {
			stderr("%s", err.Error())
			stderr("%s", sep)
		}
		stderr("Misc:")
		stderr("  rkt's appc version: %s", schema.AppContainerVersion)
		stderr("%s", sep)
		// make a visible break between errors and the listing
		stderr("")
	}

	tabOut.Flush()
	stdout("%s", tabBuffer.String())
	return 0
}

func newPodListReadError(p *pod, err error) error {
	lines := []string{
		fmt.Sprintf("Unable to read pod %s manifest:", p.uuid.String()),
		fmt.Sprintf("  %v", err),
	}
	return fmt.Errorf("%s", strings.Join(lines, "\n"))
}

func newPodListLoadError(p *pod, err error, pmj []byte) error {
	lines := []string{
		fmt.Sprintf("Unable to load pod %s manifest, because it is invalid:", p.uuid.String()),
		fmt.Sprintf("  %v", err),
	}
	pm := lastditch.PodManifest{}
	if err := pm.UnmarshalJSON(pmj); err != nil {
		lines = append(lines, "  Also, failed to get any information about invalid pod manifest:")
		lines = append(lines, fmt.Sprintf("    %v", err))
	} else {
		if len(pm.Apps) > 0 {
			lines = append(lines, "Objects related to this error:")
			for _, app := range pm.Apps {
				lines = append(lines, fmt.Sprintf("  %s", appLine(app)))
			}
		} else {
			lines = append(lines, "No other objects related to this error")
		}
	}
	return fmt.Errorf("%s", strings.Join(lines, "\n"))
}

func newPodListZeroAppsError(p *pod) error {
	return fmt.Errorf("Pod %s contains zero apps", p.uuid.String())
}

func newPodListImageStoreFailure(p *pod, err error, pm *schema.PodManifest, app schema.RuntimeApp) error {
	lines := []string{
		fmt.Sprintf("Unable to get image %s manifest from store:", app.Image.ID.String()),
		fmt.Sprintf("  %v", err),
		"Objects related to this error:",
		fmt.Sprintf("  App: %q from failing image %q (%s)",
			app.Name, app.Image.Name, app.Image.ID),
		fmt.Sprintf("  Pod %s (spec version %s) with following apps:", p.uuid.String(), pm.ACVersion.String()),
	}
	for _, pApp := range pm.Apps {
		lines = append(lines, fmt.Sprintf("    %s", appLine(degradeRuntimeApp(pApp))))
	}
	return fmt.Errorf("%s", strings.Join(lines, "\n"))
}

func newPodListImageLoadFailure(p *pod, err error, pm *schema.PodManifest, imj []byte, app schema.RuntimeApp) error {
	im := lastditch.ImageManifest{}
	imErr := im.UnmarshalJSON(imj)
	acVersion := "unknown"
	if imErr == nil {
		acVersion = im.ACVersion
	}
	lines := []string{
		fmt.Sprintf("Unable to load image %s manifest (spec version %s) because it is invalid:", app.Image.ID.String(), acVersion),
		fmt.Sprintf("  %v", err),
	}
	if imErr != nil {
		lines = append(lines, "  Also, failed to get any information about invalid image manifest:")
		lines = append(lines, fmt.Sprintf("    %v", imErr))
	}
	lines = append(lines, "Objects related to this error:")
	lines = append(lines, fmt.Sprintf("  App: %q from failing image %q (%s)",
		app.Name, app.Image.Name, app.Image.ID))
	lines = append(lines, fmt.Sprintf("  Pod %s (spec version %s) with following apps:", p.uuid.String(), pm.ACVersion.String()))
	for _, pApp := range pm.Apps {
		lines = append(lines, fmt.Sprintf("    %s", appLine(degradeRuntimeApp(pApp))))
	}
	return fmt.Errorf("%s", strings.Join(lines, "\n"))
}

func degradeRuntimeApp(app schema.RuntimeApp) lastditch.RuntimeApp {
	return lastditch.RuntimeApp{
		Name: app.Name.String(),
		Image: lastditch.RuntimeImage{
			Name: app.Image.Name.String(),
			ID:   app.Image.ID.String(),
		},
	}
}

func appLine(app lastditch.RuntimeApp) string {
	return fmt.Sprintf("App: %q from image %q (%s)",
		app.Name, app.Image.Name, app.Image.ID)
}

func fmtNets(nis []netinfo.NetInfo) string {
	var parts []string
	for _, ni := range nis {
		// there will be IPv6 support soon so distinguish between v4 and v6
		parts = append(parts, fmt.Sprintf("%v:ip4=%v", ni.NetName, ni.IP))
	}
	return strings.Join(parts, ", ")
}
