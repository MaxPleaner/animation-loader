require 'colors'
loader_utils = require 'loader-utils'

# node's method to execute shell commands synchronously
#
exec_sync = require('child_process').execSync

# parse query params into objects. Note that only one top level hash is allowed.
#
querystring_parser = require 'querystring'

# random string generator
#
randomstring = require 'randomstring'

# This loader works by creating temporary, modified versions of gifs.
# all of these are placed into a single folder, which is created here.
# Assets should not be manually placed in here.
#
asset_dir = "webm_overlay_assets"
exec_sync """
  mkdir -p #{asset_dir}
"""

# Their paths are random
#
gen_path = (extension)->
  "#{asset_dir}/#{randomstring.generate()}.#{extension}"

# Some temporary png files are created sometimes
#
gen_tmp_png_path = ->
  "#{asset_dir}/#{randomstring.generate()}%03d.png"

# all of these operations remove the path given to them
# after they've created a new file with modification. 
# that's why compile_video does an initial copy -
# that way the original isn't destroyed.

# If the 'transparent=true' query param is given,
# then two additional params will be checked:
#
# - fuzz 
#     - the amount of lenience to give when making a color transparent).
#     - a number from 0 (exact color match) to 100 (everything is transparent)
#
# - color
#     - a hexadecimal code, i.e. "000000" for black or "FFFFFF" for white
#     - this can be determined using a color picker tool such as gpick
#
# This requires imagemagick to be installed on the system.
#
to_transparent_gif = (in_gif_path, color, fuzz) ->
  console.log "making transparent".yellow

  # fuzz defaults to a small amount
  fuzz ||= 25 
  # color defaults to black
  color ||= "000000"
  new_path = gen_path("gif")
  cmd = """
    convert \
      #{in_gif_path} \
      -coalesce \
      -fuzz #{fuzz}% \
      -transparent "##{color}" \
      miff:- \
    | convert \
      -dispose background - \
      #{new_path}
  """
  exec_sync cmd
  exec_sync "rm #{in_gif_path}"
  new_path

# if the 'resize' query param is given, than its value is
# checked for dimensions e.g. 'resize=1400x1400'
# This is width then height and it will be forceful - 
# the images original resolution will not be respected.
#
# This requires imagemagick on the system.
#
to_resized = (in_gif_path, new_size) ->
  console.log "resizing".yellow

  new_path = gen_path("gif")
  exec_sync "convert #{in_gif_path} -coalesce -resize #{new_size}! #{new_path}"
  exec_sync "rm #{in_gif_path}"
  new_path

to_webm_alpha = (in_gif_path) ->
  new_path = gen_path("webm")
  tmp_png_path = gen_tmp_png_path()

  console.log "converting to webm - creating png frames".yellow
  exec_sync "convert #{in_gif_path} -coalesce #{tmp_png_path}"

  console.log "converting to webm - combining frames".yellow
  exec_sync """
    ffmpeg -f image2 -i #{tmp_png_path} -c:v libvpx -pix_fmt yuva420p #{new_path}
    rm #{asset_dir}/*png
  """
  exec_sync "rm #{in_gif_path}"
  new_path

# The entry point of this loader.
# It gets passed a full path with query params at the end.
# If no query params are given, nothing will happen and the path will be returned.
#
compile_video = (remaining_request) ->

  [full_path, querystring] = remaining_request.split("?")
  query = querystring_parser.parse querystring

  path = "#{asset_dir}/#{randomstring.generate()}.gif"
  exec_sync "cp #{full_path} #{path}"

  console.log "compiling gif: #{full_path} with params:".yellow
  console.log query

  { transparent, resize, to_webm, color, fuzz } = query

  if transparent
    path = to_transparent_gif(path, color, fuzz)

  if resize
    path = to_resized(path, resize) 

  if to_webm
    path = to_webm_alpha(path)

  console.log "done".green
  path
  
# The exported function
# Webpack loader boiler, calls our function
#
module.exports = (source) ->
  @cachable && @cachable()
  remaining_request = loader_utils.getRemainingRequest this
  result = compile_video remaining_request
  @callback null, result 
