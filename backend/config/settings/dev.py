from .base import *  # noqa

DEBUG = True

# During development (no SMS integration yet), use explicit dev OTP mode.
OTP_DEV_BYPASS_ENABLED = True
OTP_DEV_ACCEPT_ANY_4_DIGITS = True
OTP_DEV_TEST_CODE = "0000"
OTP_DEV_ACCEPT_ANY_CODE = True
