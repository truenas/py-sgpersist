from setuptools import Extension, setup
from Cython.Build import cythonize


extensions = [
    Extension(
        'libsgpersist',
        ['libsgpersist.pyx'],
        libraries=['sgutils2']
    )
]

setup(
    name='libsgpersist',
    version='0.1',
    setup_requires=[
        'setuptools>=45.0',
        'Cython',
    ],
    ext_modules=cythonize(extensions),
)
