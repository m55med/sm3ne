"""Password hashing helpers.

We use bcrypt with an explicit work factor (rounds=12). 12 is bcrypt's library
default today but pinning it makes the intent obvious and survives future
default changes upstream. ~250ms / hash on modern hardware — strong enough
without being a DoS vector on login bursts.
"""
import bcrypt


# Pinned so future bcrypt releases that change the default don't silently shift
# our cost factor.
BCRYPT_ROUNDS = 12


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=BCRYPT_ROUNDS)).decode()


def verify_password(password: str, hashed: str) -> bool:
    return bcrypt.checkpw(password.encode(), hashed.encode())
