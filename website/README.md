# Website

Website for IdLE, built using [Docusaurus](https://docusaurus.io/).

## Prerequisites

[NodeJS](https://nodejs.org/en/download/current)

## Local Development

This command starts a local development server and opens up a browser window. Most changes are reflected live without having to restart the server.

```powershell
cd <repo>\website
npm install
npm start
```

Cached changes (e.g. changes in docusaurus.conf.js or plugins usually require local cache removal and manual restart.

```powershell
cd <repo>\website
Remove-Item -Recurse -Force .docusaurus
npm start
```

## Synchronized Assets

The custom script `website/scripts/sync-assets.js` is used to keep assets from `docs/assets` to `website/static/assets` as Docusaurus requires statics to be served from there.

Run the script via

```powershell
cd <repo>\website
npm run sync-assets
```

## Build

```powershell
npm run build
```

## Deployment

TBD
