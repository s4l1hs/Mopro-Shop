package softdeleteduser_test

import (
	"testing"

	"golang.org/x/tools/go/analysis/analysistest"

	"github.com/mopro/platform/cmd/lint-discipline/softdeleteduser"
)

func TestSoftDeletedUser(t *testing.T) {
	analysistest.Run(t, analysistest.TestData(), softdeleteduser.Analyzer, "b")
}
