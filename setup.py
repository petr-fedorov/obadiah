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
