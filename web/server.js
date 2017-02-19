// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

'use strict'

const fs = require('fs')
const qs = require('qs')
const url = require('url')
const pug = require('pug')
const http = require('http')
const YAML = require('js-yaml')
const request = require('request')
const process = require('process')
const getRawBody = require('raw-body')

// TODO:
// - Generate index pages from global configuration.
// - Allow configuration of additional API requests.

// Set working directory to web.
process.chdir('./web')

// Load static files.
const staticFiles = {
  '/favicon.ico': fs.readFileSync('favicon.ico')
}

// Load configuration.
const config = YAML.safeLoad(fs.readFileSync('config.yaml'))
const port = config.port
const apiBase = config.apiBase

// Map with compiled template functions.
const pugCache = {}

// Map with additional template YAML data.
const yamlCache = {}

// Not-found template.
const notFound = pug.compileFile('views/404.pug')

// Template utility functions.
const templateUtils = {
  'ucfirst': (str) => str.charAt(0).toUpperCase() + str.slice(1)
}

// Finalize request.
function finishRequest (response, method, path, body, templateData) {
  // Note that it is OK to pass body: null, it will be ignored.
  // (see paramsHaveRequestBody() in request source in lib/helpers.js)
  request({
    method: method,
    baseUrl: apiBase,
    url: path,
    json: true,
  body: body}, (error, apiResponse, apiBody) => {
    // If the response is an error with message:
    // No method found matching HTTP method...
    // Then do not forward the status code.
    if (!(apiBody && apiBody.error &&
      apiBody.error.message.startsWith('No method found matching HTTP method'))) {
      response.statusCode = apiResponse.statusCode
    }

    // Add API request and response body to template data.
    templateData['request'] = body
    templateData['data'] = apiBody

    // Render page.
    response.end(pugCache[path](templateData))
  })
}

// Global request handler.
const requestHandler = (request, response) => {
  console.log(`${request.method} ${request.url}`)

  // Return static files.
  if (request.url in staticFiles) {
    response.end(staticFiles[request.url])
  } else {
    // Prepare response.
    response.setHeader('Content-Type', 'text/html')

    // Normalize URL.
    let path = request.url
    if (path.endsWith('/')) {
      path += 'index'
    }

    // Initial template data.
    const templateData = {
      'global': config.templateConstants,
      'path': path.split('/').slice(1),
      'utils': templateUtils
    }

    // Find HTML template.
    if (!(path in pugCache)) {
      const pugFile = `views${path}.pug`
      if (fs.existsSync(pugFile)) {
        pugCache[path] = pug.compileFile(pugFile)
      } else {
        pugCache[path] = false
      }
    }

    // Return Not-Found if HTML template does not exist.
    if (pugCache[path] === false) {
      response.statusCode = 404
      response.end(notFound(templateData))
    } else {
      // Find YAML data file.
      if (!(path in yamlCache)) {
        const yamlFile = `views${path}.yaml`
        if (fs.existsSync(yamlFile)) {
          yamlCache[path] = YAML.safeLoad(fs.readFileSync(yamlFile))
        } else {
          yamlCache[path] = false
        }
      }

      // Add YAML data to template data.
      templateData['local'] = yamlCache[path]
      if (templateData['local'] === false) {
        templateData['local'] = {}
      }

      // If this is a POST request, then parse the body.
      if (request.method == 'POST') {
        getRawBody(request, (error, string) => {
          const data = qs.parse(string)
          finishRequest(response, request.method, path, data, templateData)
        })
      } else {
        finishRequest(response, request.method, path, null, templateData)
      }
    }
  }
}

// Create HTTP server.
const server = http.createServer(requestHandler)

// Start listening on the specified port.
server.listen(port, (error) => {
  if (error) {
    return console.log('something bad happened', error)
  } else {
    console.log(`server is listening on ${port}`)
  }
})
