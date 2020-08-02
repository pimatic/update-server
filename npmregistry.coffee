Promise = require 'bluebird'
prequest = require 'request-promise'
request = require 'request'
exec = require('child_process').exec

JSONStream = require('JSONStream')
es = require('event-stream')

fs = require('fs')
Promise.promisifyAll(fs)

module.exports = {

  getInfo: (name) ->
    prequest("https://registry.npmjs.org/#{name}").then( (res) ->
      info = JSON.parse(res)
      if info.error?
        throw new Error("getting info about #{name} failed: #{info.reason}")
      return fs.writeFileAsync("cache/#{name}.json", res)
        .then( () => info )
    )

  getInfoCached: (name) ->
    return fs.readFileAsync("cache/#{name}.json").then( (data) =>
      return JSON.parse(data)
    )

  getAllPlugins: () ->
    console.log "Fetching plugins"
    last = null
    count = 0
    return new Promise( (resolve, reject) =>
      packages = []
      request(url: 'https://registry.npmjs.org/-/v1/search?text=pimatic-&size=250', (error, response, body) =>
          if error
            console.error(error, response.statusCode)
            reject(error)
        )
        .pipe(JSONStream.parse('objects..name'))
        .on('error', (err) ->
          console.error(err)
          reject(err)
        )
        .pipe es.mapSync (data) ->
          count++
          last = data
          if data.indexOf("pimatic-") is 0
            return data
          else
            return
        .pipe es.writeArray (err, data) ->
          if(err)
            reject(err)
          else
            if data.length > 10
              data.sort()
              resolve(data)
            else
              reject(new Error('Incomplete data from npm registry: ' + data))
    )

  getPluginListCached: () ->
    return fs.readFileAsync('cache/pluginlist.json').then( (data) =>
      return JSON.parse(data)
    ).catch( (err) ->
      if(err.code == 'NOENT')
        return []
      throw err
    )

  getPluginList: () ->
    return this.getAllPlugins().then( (allPlugins) =>
      blacklist = [
        'pimatic-plugin-template', 'pimatic-rest-api', 'pimatic-speak-api',
        "pimatic-datalogger", "pimatic-redirect", "pimatic-datalogger",
        "pimatic-homeduino-dst-dev", "pimatic-iwy-light-master", "pimatic-weather",
        "pimatic-pilight", "pimatic-plugin-iwy-light-master", "pimatic-dhtxx",
        "pimatic-plugin-commons"
      ]
      plugins = (
        for p in allPlugins
          continue if p.length is 0 or p in blacklist
          p
      )
      plugins = ["pimatic"].concat plugins
      return fs.writeFileAsync('cache/pluginlist.json', JSON.stringify(plugins))
        .then( () => plugins )
    )

}