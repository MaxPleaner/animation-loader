# String#blue and stuff
require 'colors'

# Webpack loader boiler
loader_utils = require 'loader-utils'

# node's method to execute shell commands synchronously
exec_sync = require('child_process').execSync

# parse query params into objects. Note that only one top level hash is allowed.
querystring_parser = require 'querystring'

# random string generator
randomstring = require 'randomstring'

# filesystem
fs = require 'fs'

# This loader works by creating temporary, modified versions of gifs.
# all of these are placed into a single folder, which is created here.
# Assets should not be manually placed in here.
# It is emptied whenever the server starts
#
asset_dir = "./.animation-loader"
exec_sync """
  rm -rf #{asset_dir}
  mkdir -p #{asset_dir}
  touch .merge.gif
"""

# Their paths are random, although if the 'name' param is given
# then the file will be renamed to have that identifier. 
#
gen_path = (extension)->
  "#{asset_dir}/#{randomstring.generate()}.#{extension}"

# Some temporary png files are created during the conversion to webm
#
gen_tmp_png_path = ->
  "#{asset_dir}/#{randomstring.generate()}%03d.png"

# all of these operations remove the path given to them
# after they've created a new file with modification. 
# that's why compile_video does an initial copy -
# that way the original isn't destroyed.
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

get_num_frames = (path) ->    
  frames_text = exec_sync("""
    identify -format '%T,%w,%h ' "#{path}"
  """).toString()
  num_frames = frames_text.split(" ").length
  num_frames

# In case the background is shorter than the foreground, it needs to be looped.
# the output of this method is a string like "0-16,0-9" representing the
# sequences of frames to play
#
# This doesn't yet support backgrounds that are longer than foregrounds;
# they will be automatically shortened
#
build_bg_frame_ranges = (bg_frames, fg_frames) ->
  if fg_frames < bg_frames
    "0-#{fg_frames-2}" # Don't know why, but it's -2 and not -1
  else
    full_bg = "0-#{bg_frames-1}"
    full_loops = Math.floor(fg_frames / bg_frames)
    remainder = fg_frames % bg_frames
    result = ([0...full_loops].map => full_bg).join(",")
    if remainder > 0
      result += "," if full_loops > 0
      result += "0-#{remainder-1}"
    result

DeferMerge = ->
DeferMerge.prototype = new Error()

file_ready = (path) ->
  fs.existsSync path

to_merged = ({background, foreground, size}) ->
  new_path = gen_path("gif")
  [tmp1, tmp2] = (gen_path("png") for [1..2])
  bg_path = "#{asset_dir}/#{background}.gif"
  fg_path = "#{asset_dir}/#{foreground}.gif"
  if !([bg_path, fg_path].every file_ready)
    console.log "deferring merge".yellow
    throw new DeferMerge

  bg_frames = get_num_frames bg_path
  fg_frames = get_num_frames fg_path
  bg_frame_ranges = build_bg_frame_ranges(bg_frames, fg_frames)
  console.log """
    merging 
      bg: #{background}(#{bg_frame_ranges}) 
      fg: #{foreground}(#{fg_frames})
  """.blue
  exec_sync """
    montage                        \
      -background none             \
      #{fg_path}                   \
      -tile x1@ -geometry +0+0     \
      #{tmp1}

    montage                        \
      #{bg_path}[#{bg_frame_ranges}] \
      -tile x1@ -geometry +0+0     \
      #{tmp2}

    convert                             \
      -delay 10 -loop 0 #{tmp2} #{tmp1} \
      -coalesce -flatten                \
      -crop #{size} +repage             \
      #{new_path}

    rm #{tmp1} #{tmp2}
  """

  # If the images being merged are not the same size,
  # there will be a bug where the merged gif is correct for the correct
  # length, but there are extra frames with glitchy stuff.
  #
  # To circumvent this the image gets cropped to the expected length.
  #
  new_path_2 = gen_path("gif")
  exec_sync """
    convert #{new_path}[0-#{fg_frames - 2}] #{new_path_2}
    rm #{new_path}
  """

  new_path_2

# The entry point of this loader.
# It gets passed a full path with query params at the end.
# If no query params are given, nothing will happen and the path will be returned.
#
compile_video = (remaining_request) ->

  failed = false

  [full_path, querystring] = remaining_request.split("?")
  query = querystring_parser.parse querystring

  # Merge is not like the rest of the params.
  # It begins by require being passed a special path which ends in ".merge.gif"
  # This file is automatically created by the loader in the root of the repo.
  merge = full_path.endsWith ".merge.gif"

  path = "#{asset_dir}/#{randomstring.generate()}.gif"
  exec_sync "cp #{full_path} #{path}" unless merge

  console.log "compiling gif: #{full_path} with params:".yellow
  console.log query

  {
    transparent, resize, to_webm, color, fuzz,
    background, foreground, size, name
  } = query

  # merge first
  try
    if merge
      path = to_merged({background, foreground, size})
  catch error
    if error instanceof DeferMerge
      failed = true
    else
      throw error

  return if failed

  # resize early so the other transformations are less work
  if resize
    path = to_resized(path, resize) 

  if transparent
    path = to_transparent_gif(path, color, fuzz)

  # convert to webm last since it can't be transformed any more.
  if to_webm

    path = to_webm_alpha(path)

  if name
    ext = if to_webm then "webm" else "gif"
    new_path = "#{asset_dir}/#{name}.#{ext}"

    exec_sync("rm #{new_path}") if fs.existsSync(new_path)
    exec_sync """
      mv #{path} #{new_path}
    """
    path = new_path

  path
  
# The exported function
# Webpack internals call this
#
module.exports = (source) ->
  @cachable && @cachable()
  remaining_request = loader_utils.getRemainingRequest this
  result = compile_video remaining_request
  @callback(null, result) if result
