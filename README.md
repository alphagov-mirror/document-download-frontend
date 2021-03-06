# document-download-frontend
GOV.UK Notify Document Download frontend user application

## First-time setup

Brew is a package manager for OSX. The following command installs brew:
```shell
    /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

Languages needed
- Python 3.6
- [Node](https://nodejs.org/) 12.14.1 or greater
- [npm](https://www.npmjs.com/) 6.13.4 or greater
```shell
    brew install node
```


[NPM](npmjs.org) is Node's package management tool. `n` is a tool for managing
different versions of Node. The following installs `n` and uses the long term support (LTS)
version of Node.
```shell
    npm install -g n
    n lts
    npm rebuild node-sass
```

The app runs within a virtual environment. We use mkvirtualenv for easier working with venvs
```shell
    pip install virtualenvwrapper
    mkvirtualenv -p /usr/local/bin/python3 document-download-frontend
```

Install dependencies and build the frontend assets:
```shell
    workon document-download-frontend
    ./scripts/bootstrap.sh
```

## Rebuilding the frontend assets

If you want the front end assets to re-compile on changes, leave this running
in a separate terminal from the app
```shell
    npm run watch
```

## Running the application
```shell
make run
```

## Updating application dependencies

The `requirements.txt` file is generated from the `requirements-app.txt` in order to pin
versions of all nested dependencies. If `requirements-app.txt` has been changed (or
we want to update the unpinned nested dependencies) `requirements.txt` should be
regenerated with

```
make freeze-requirements
```

`requirements.txt` should be committed alongside `requirements-app.txt` changes.
