package sizefinder

import "errors"

// ErrProfileNotFound: the user has no fit profile yet.
var ErrProfileNotFound = errors.New("sizefinder: fit profile not found")

// ErrInvalidMeasurement: a measurement is outside sane human bounds.
var ErrInvalidMeasurement = errors.New("sizefinder: measurement out of range")
