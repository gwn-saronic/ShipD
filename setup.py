from setuptools import setup, find_packages
import re
import os

__version__ = re.findall(
    r"""__version__ = ["']+([0-9\.]*)["']+""",
    open("shipd/__init__.py").read(),
)[0]

this_directory = os.path.abspath(os.path.dirname(__file__))
with open(os.path.join(this_directory, "README.md"), encoding="utf-8") as f:
    long_description = f.read()

setup(
    name="shipd",
    version=__version__,
    description="ShipD is package for ship analysis and design",
    long_description=long_description,
    long_description_content_type="text/markdown",
    keywords="",
    author="",
    author_email="",
    url="https://github.com/noahbagz/ShipD",
    license="",
    packages=find_packages(include=["shipd*"]),
    install_requires=[
        "numpy>=1.16",
    ],
    classifiers=[
        "Operating System :: OS Independent",
        "Programming Language :: Python",
    ],
)
