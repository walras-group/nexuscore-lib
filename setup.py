import os
import platform
from pathlib import Path

from Cython.Build import cythonize
from setuptools import Extension
from setuptools import setup


IS_WINDOWS = platform.system() == "Windows"
IS_LINUX = platform.system() == "Linux"

extra_compile_args = []
extra_link_args = []
if not IS_WINDOWS:
    extra_compile_args += ["-O2", "-Wno-unreachable-code"]
if IS_LINUX:
    # Strip symbols at link time to keep the shared objects small.
    extra_link_args += ["-Wl,-s"]

extensions = [
    Extension(
        str(pyx.with_suffix("")).replace(os.sep, "."),
        [str(pyx)],
        extra_compile_args=extra_compile_args,
        extra_link_args=extra_link_args,
    )
    for pyx in Path("nexuscore").rglob("*.pyx")
]

setup(
    ext_modules=cythonize(
        extensions,
        compiler_directives={
            "language_level": "3",
            "cdivision": True,
            "nonecheck": True,
            "embedsignature": True,
        },
        nthreads=os.cpu_count() or 1,
    ),
)
