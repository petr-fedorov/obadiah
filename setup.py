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


from setuptools import setup, find_packages
setup(
    name="obadiah",
    version="0.1.4",
    python_requires=">=3.6",
    packages=find_packages('python'),
    package_dir={'': 'python'},
    entry_points={
        'console_scripts': [
            'obadiah = obadiah.__main__:main'
        ]
    },
    install_requires=[
        'psycopg2-binary',
        'websockets',
        'asyncpg',
        'aiohttp',
        'cchardet',
        'aiodns',
        'sslkeylog'
    ],



)
