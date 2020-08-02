express = require 'express'
Promise = require 'bluebird'
PluginMonitor = require('./monitor').PluginMonitor
fs = require 'fs'; Promise.promisifyAll(fs)
_ = require 'lodash'
semver = require 'semver'

monitor = new PluginMonitor()
monitor.start()

monitor.on 'update', (info) => console.log info.name, info['dist-tags'].latest

app = express()

app.set('json spaces', '  ')

getOnlyLatest = (packageInfo) ->
  latest = packageInfo.versions[packageInfo['dist-tags'].latest]
  latest.dists = packageInfo.dists
  return latest

getLatestCompatible = (refVersion) ->
  return (packageInfo) ->
    result = packageInfo.versions[packageInfo['dist-tags'].latest]
    result.dists = packageInfo.dists
    if isCompatible(refVersion, result)
      return result
    else
      satisfyingV = satisfyingVersion(packageInfo, refVersion)
      if satisfyingV.length > 0
        latestSatisfying = satisfyingV[satisfyingV.length-1]
        result = packageInfo.versions[latestSatisfying]
        result.dists = packageInfo.dists
        return result
      else
        # no compatible version found, return latest
        return result
    return result

onlyPluginsFilter = (p) -> p.name isnt "pimatic"

isCompatible = (refVersion, packageInfo) ->
  try
    peerVersion = packageInfo.peerDependencies?.pimatic
    if peerVersion?
      if semver.satisfies(refVersion, peerVersion)
        return true
  catch err
    console.log(err)
  return false

satisfyingVersion = (p, refVersion) ->
  versions = []
  _.forEach(p.versions, (value, key) =>
    if isCompatible(refVersion, value)
      versions.push key
  )
  return versions

getCompatibleCore = (refVersion, packageInfo) ->
  refVersion = (
    if semver.satisfies(refVersion, "0.8.*") then "0.8.*"
    else ">=0.9.0"
  )
  latest = packageInfo['dist-tags'].latest
  result = packageInfo.versions[latest]
  result.dists = packageInfo.dists
  if semver.satisfies(latest, refVersion)
    return result
  else
    compatibleVersions = Object.keys(packageInfo.versions).filter( (version) ->
      return semver.satisfies(version, refVersion)
    )
    if compatibleVersions.length > 0
      latestSatisfying = compatibleVersions[compatibleVersions.length-1]
      result = packageInfo.versions[latestSatisfying]
      result.dists = packageInfo.dists
      return result
  return result

app.get('/plugins', (req, res) ->
  version = req.query.version or "0.8.100"
  unless semver.valid(version)?
    return res.send({error: "Invalid version"})
  monitor.getNpmInfos().done( (plugins) ->
    plugins = plugins.filter(onlyPluginsFilter)
    plugins = _.map(plugins, getLatestCompatible(version))
    res.send(plugins)
  )
  return
)

app.get('/core', (req, res) ->
  version = req.query.version or "0.8.100"
  unless semver.valid(version)?
    return res.send({error: "Invalid version"})
  monitor.getNpmInfos().done( (plugins) ->
    res.send(getCompatibleCore(version, plugins[0]))
  )
  return
)

mapMaintainers = (p) ->
  latestVersion = p['dist-tags'].latest
  v08versions = satisfyingVersion(p, '0.8.100')
  v09versions = satisfyingVersion(p, '0.9.0')
  return {
    name: p.name,
    author: p.author
    maintainers: p.maintainers
    latest: latestVersion
    time: p.time[latestVersion]
    repository: p.repository
    license: p.license
    latestV08: (if v08versions.length > 0 then v08versions[v08versions.length-1] else null)
    latestV09: (if v09versions.length > 0 then v09versions[v09versions.length-1] else null)
  }

app.get('/maintainers', (req, res) ->
  monitor.getNpmInfos().done( (plugins) ->
    res.send(_.map(plugins.filter( (p) -> p.name isnt "pimatic"), mapMaintainers))
  )
  return
)

personToHtml = (p) -> "<a href=\"#{p.url}\">#{p.name}</a> (#{p.email})"

app.get('/maintainers-table', (req, res) ->
  monitor.getNpmInfos().done( (plugins) ->
    html = '<html><head><title>pimatic plugins</title>'
    html += '<meta name="robots" content="noindex" />'
    html += '<style>
      table {
          border-collapse: collapse;
          width: 100%;
      }

      th, td {
          text-align: left;
          padding: 8px;
      }

      tr:nth-child(even){background-color: #f2f2f2}

      th {
          background-color: #4CAF50;
          color: white;
      }
    </style>'
    html += '</head><body>'

    html += '<table>'
    html += '<tr><th>Name</th><th>Author</th><th>Maintainers</th><th>Version</th><th>Release Time</th><th>License</th><th>0.8 version</th><th>0.9 version</th></tr>'
    _.map(plugins.filter(onlyPluginsFilter), mapMaintainers).forEach( (p) =>
      htmlMaintainers = _.map(p.maintainers, personToHtml).join('<br>')
      htmlAuthor = if p.author? then personToHtml p.author else p.author
      html += """<tr>
        <td>#{p.name}</td>
        <td>#{htmlAuthor}</td>
        <td>#{htmlMaintainers}</td>
        <td>#{p.latest}</td>
        <td>#{p.time}</td>
        <td>#{p.license}</td>
        <td>#{p.latestV08}</td>
        <td>#{p.latestV09}</td>
      </tr>"""
    )
    html += '</table>'
    html += '</body></html>'
    res.send(html);
  )
  return
)

app.get('/download/:plugin/:file', (req, res) ->
  notFound = () -> res.status(404).end("Not Found")
  monitor.getNpmInfos().done( (plugins) ->
    parts = req.params.file.replace('.tar.gz', '').split("-")
    if parts.length isnt 5
      console.log "wrong size"
      return notFound()
    name = req.params.plugin
    [node, abi, arch, platform, version] = parts
    plugin = _.find(plugins, (p) -> p.name is name)
    unless plugin?
      console.log "not found"
      return notFound()
    prefix = "#{node}-#{abi}-#{arch}-#{platform}"
    for dist in plugin.dists
      if dist.name.indexOf(prefix) is 0
        if version is "latest"
          return res.redirect(dist.tarball_url)
    console.log "dist not found"
    return notFound()
  )
  return
)



# ---
# generated by js2coffee 2.0.1

server = app.listen(9090, ->
  host = server.address().address
  port = server.address().port
  console.log 'Update-server listening at http://%s:%s', host, port
  return
)
