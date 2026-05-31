package inbox

import "errors"

var (
	ErrInvalidPreference = errors.New("inbox: invalid preference category/channel")
	ErrInvalidPlatform   = errors.New("inbox: invalid push platform")
	ErrInvalidPushToken  = errors.New("inbox: empty push token")
)
