# Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation,  version 2 of the License

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.


# Shall we run in single test mode? Used when we develop a new test and want to run only the new one.
SINGLE <- FALSE

# Shall we run integration tests for Bitstamp?
BITSTAMP <- TRUE
# Shall we run integration tests for Bitfinex?
BITFINEX <- TRUE

# Shall we run short integration tests? The short tests are needed to check whether function at least works
SHORT <- TRUE

# Shall we run long integration tests? The long tests checks whether function works correctly
LONG <- TRUE
