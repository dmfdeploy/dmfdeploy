# dmfdeploy.io local prototype

This static Astro site builds the homepage and `/sponsor` route from the
Control plane design studies. It is a local review surface. Payment and
production deployment are inactive.

## Run locally

```sh
cd site
npm ci
npm run dev
```

Open `http://127.0.0.1:4321/` and `http://127.0.0.1:4321/sponsor`.

## Check and build

```sh
npm run check
npm run build
npm run test:visual
```

Astro pre-renders both routes. The future Cloudflare Pages project can use
`site` as its root directory, `npm run build` as its build command, and `dist`
as its output directory. No Cloudflare adapter is needed for static output.

The checked-in film is a web-sized derivative of the publish-cleared film 006.
The poster uses the project's own mark and a frame from that film. The source
master stays in the content repository. No payment endpoint, form, or checkout
code is present. Fiscal hosting, Open Collective reporting, invoicing, and
sponsorship terms require confirmation before any payment route is added.
