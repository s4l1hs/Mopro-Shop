package b

import "identity"

func violationNoGuard(repo identity.Repository) string {
	u, _ := repo.GetUser(1) // want `soft-deleted-user-consumer`
	return u.Status
}

func okWithGuard(repo identity.Repository) string {
	u, _ := repo.GetUser(1)
	if u.Status == identity.StatusDeleted {
		return "deleted"
	}
	return u.Status
}

//nolint:soft-deleted-user-consumer
func okWithNolint(repo identity.Repository) string {
	u, _ := repo.GetUser(1) // admin path — intentionally wants deleted users
	return u.Status
}

func okDiscardedUser(repo identity.Repository) bool {
	_, err := repo.GetUser(1) // existence check — user discarded — fine
	return err == nil
}

func okFreshUser(repo identity.Repository) string {
	u, _ := repo.CreateUser("x") // Create, not a reader — fresh user — fine
	return u.Status
}
