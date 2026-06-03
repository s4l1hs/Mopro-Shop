package pooltx_test

import (
	"testing"

	"golang.org/x/tools/go/analysis/analysistest"

	"github.com/mopro/platform/cmd/lint-discipline/pooltx"
)

func TestPoolTx(t *testing.T) {
	analysistest.Run(t, analysistest.TestData(), pooltx.Analyzer, "a")
}
