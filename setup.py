from setuptools import setup, find_packages
setup(
    name="obadiah",
    version="0.1.3",
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
        'pusherclient',
        'websockets',
        'asyncpg',
        'aiohttp',
        'cchardet',
        'aiodns'
    ],



)
