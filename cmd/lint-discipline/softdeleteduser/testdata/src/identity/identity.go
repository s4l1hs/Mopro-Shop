package identity

const StatusDeleted = "deleted"

type User struct{ Status string }

// Repository is the dumb store (its reads are unguarded — consumers must guard).
type Repository interface {
	GetUser(id int64) (User, error)
	CreateUser(name string) (User, error)
}
