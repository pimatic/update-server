Promise = require 'bluebird'
npmregistry = require('./npmregistry')
events = require('events')

onError = (error) -> console.error error.stack

class PluginMonitor extends events.EventEmitter

  pluginsList: null
  packageInfos: null

  constructor: ->
    super()
    @pluginsList = npmregistry.getPluginListCached().then( (plugins) =>
      @packageInfos = Promise.map(@pluginsList, (name) =>
        return npmregistry.getInfoCached(name)
      ).catch( (error) =>
        onError(error)
        @packageInfos = null
      )
      return plugins
    )

  updatePluginList: =>
    oldPluginsList = @pluginsList or Promise.resolve([])
    pending = npmregistry.getPluginList()
      .then( (plugins) =>
        return oldPluginsList.then( (oldPlugins) =>
          if plugins.length is 0
            # something went wrong
            plugins = oldPlugins
          @pluginsList = Promise.resolve(plugins)
          for p in plugins
            unless p in oldPlugins
              @emit 'new', p
          return @pluginsList
        )
      ).catch(onError)
    unless @pluginsList?
      @pluginsList = pending
    # reschedule next hour to update
    setTimeout(@updatePluginList, 60*60*1000)

  updateNpmInfos: =>
    oldPackageInfos = @packageInfos or Promise.resolve([])
    pending = oldPackageInfos.then( (oldPackageInfos) =>
      return @pluginsList.map( (name) =>
        return npmregistry.getInfo(name).then( (info) =>
          @_checkForUpdate(oldPackageInfos, info)
          return info
        ).catch( (error) =>
          onError(error)
          return Promise.resolve()
        )
      ).filter( (p) => p? ).then( (infos) =>
        return @packageInfos = Promise.resolve(infos)
      )
    ).catch(onError)
    unless @packageInfos?
      @packageInfos = pending
    # reschedule next 5min
    setTimeout(@updateNpmInfos, 5*60*1000)

  start: ->
    @updatePluginList()
    @updateNpmInfos()

  _checkForUpdate: (oldPackageInfos, info) ->
    for op in oldPackageInfos
      if op.name is info.name
        if op.version isnt info.version
          @emit 'update', info
        return
    @emit 'update', info
    return

  getPluginList: -> @pluginsList
  getNpmInfos: -> @packageInfos

module.exports = {PluginMonitor}