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

tzlist <- OlsonNames()
config <- config::get()
Sys.chmod(config$sslkey, mode="0600")
durations <- list("3 seconds"=3,
   "15 seconds"=15,
   "30 seconds"=30,
   "1 minute"=60,
   "3 minute"=180,
   "5 minutes"=300,
   "15 minutes"=900,
   "30 minutes"=1800,
   "1 hour"=3600,
   "3 hours"=10800,
   "6 hours"=21600,
   "12 hours"=43200,
   "1 day"=86400,
   "2 day"=86400*2,
   "3 day"=86400*3,
   "4 day"=86400*4
)

frequencies <- list("All"=0,
     "5 seconds"=5,
     "10 seconds"=10,
     "15 seconds"=15,
     "30 seconds"=30,
     "1 minute"=60,
     "10 minutes"=600)

