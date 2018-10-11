from setuptools import setup, find_packages
setup(
    name="obanalyticsdb",
    version="0.1",
    packages=find_packages('python'),
    package_dir={'': 'python'},
    entry_points={
        'console_scripts': [
            'obanalyticsdb = obanalyticsdb.__main__:main'
        ]
    },
    install_requires=[
        'psycopg2-binary',
        'websocket-client',
        'btfxwss',
        'pusherclient'
    ],



)
