### About

This is a webpack loader which takes gifs as its input. Specifically, it takes their path as the value to `require`, and
the query params of the path are read for further instructions. The output (return value of `require`) is a string - 
a temporary path of a modified gif or webm.

Only gifs can receive modifications (so far), but the modified gifs can be converted to webm (preserving resizing and transparency).

### Building a sample webpack application with animation-loader

1. _NPM packages_  

    ```sh
    npm install --save webpack webpack-dev-server
    npm install --save jquery coffee-loader # this is optional, but it's used for this guide
    npm install --save animation-loader
    ```

    also add this in the scripts section of `package.json`:  

    ```json
    "scripts": { "dev": "./node_modules/.bin/webpack-dev-server --content-base . --inline --hot" }
    ```

2. _System dependencies_  

   This loader makes use of childProcess calls and requires the system to have 
   these Unix programs (these instructions for Ubuntu, but they're common libraries and should be available 
   on most distributions and osX):
    ```sh
    sudo apt-get install ffmpeg imagemagick
    ```

2. In `webpack.config.js`:  

   This sets up `loader.coffee` to be the entry point of the application.  
   `bundle.js` is an in-memory concatenation built by webpack.  
    ```js
    module.exports = {
      entry: './loader.coffee',
      output: {
        filename: 'bundle.js'
      },

      module: {
        loaders: [
          { test: /\.coffee$/, loader: "coffee-loader" },
          { test: /\.gif$/, loader: ['raw-loader', "animation-loader"] },
        ]
      },

      resolve: {
        extensions: [".coffee", ".js", ".gif"],
      }
    }

    ```

3. Place the following gif saved as `octopus.gif` in the root of the repo:  

   _note_ I i did not create this, got it by literally searching google images for 'gif'
  
  ![octopus gif](./octopus.gif)


4. Add this small `index.html` file:  

  ```html
  <!doctype html>
  <html lang="en">
      <head></head>
      <body><script src="bundle.js"></script></body>
  </html>
  ```

5. Populate `loader.coffee` with this:  

  ```coffee
  $ = require 'jquery'
  $ ->
    webm_path = require "./octopus.gif?transparent=true&color=00AEFF&resize=150x100"
    $("body").append($ """
      <video autoplay loop src="./#{foo}">
    """)
  ```

6. Start the server with `npm run dev` and visit http://localhost:8080

7. Observe the following image now present on the page:  

   ![modified gif](./modified-octopus.gif)  

   It has been resized and also made transparent on the light blue color `#00AEFF`.  


### API details

Once the webpack setup is in place, there's only one place this loader becomes relevant and that's `require`. With the proper
`test` definition in `webpack.config.js` (shown above), `gif` paths passed to `require` will pass through both the raw-loader and animation-loader.

If nothing else is given besides the path, the return value will be the absolute path:

```coffee
the_path = require './octopus.gif'
console.log the_path 
# => "/home/max/my_game/octopus.gif"
```

Anything else is found in the query params. Here is the full list of keys:

- `transparent` if this is truthy then the following keys are checked (only `color` is required):
  - `color` a hex code like `000000` (black) or `FFFFFF` (white)
  - `fuzz` (defaults to 25) the percent leniency when turning color into transparency
- `resize` the value is a width/height such as `"1400x1400"`
- `to_webm` a boolean. the output path will be webm
