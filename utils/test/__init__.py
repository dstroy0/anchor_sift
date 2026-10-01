# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Makes utils/test/ a package so its scripts run as `python -m utils.test.<name>`, which puts the root on
# sys.path and lets them import utils.tools.findroot. Run as a bare path, sys.path[0] is utils/test/ and that
# import cannot resolve.
