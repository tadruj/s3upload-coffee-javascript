# S3 CORS upload

# http://docs.amazonwebservices.com/AmazonS3/latest/dev/cors.html#how-do-i-enable-cors
# http://www.ioncannon.net/programming/1539/direct-browser-uploading-amazon-s3-cors-fileapi-xhr2-and-signed-puts/
# https://github.com/carsonmcdonald/direct-browser-s3-upload-example

class window.S3Upload
	s3_sign_put_url: '/signS3put'
	file_dom_selector: '#file_upload'

	onFinishS3Put: (public_url, file) ->
		console.log 'base.onFinishS3Put()', public_url, file

	onProgress: (percent, status, public_url, file) ->
		console.log 'base.onProgress()', percent, status, public_url, file

	onError: (status, file) ->
		console.log 'base.onError()', status, file

	# Don't override these

	constructor: (options = {}) ->
		_.extend(this, options)
		@handleFileSelect jQuery(@file_dom_selector).get(0)

	handleFileSelect: (file_element) ->
		@onProgress 0, 'Upload started.'
		files = file_element.files
		for f in files
			@uploadFile(f)

	createCORSRequest: (method, url) ->
		xhr = new XMLHttpRequest()
		if xhr.withCredentials?
			xhr.open method, url, true
		else if typeof XDomainRequest != "undefined"
			xhr = new XDomainRequest()
			xhr.open method, url
		else
			xhr = null
		xhr

	executeOnSignedUrl: (file, callback) ->
		this_s3upload = this

		xhr = new XMLHttpRequest()
		xhr.open 'GET', @s3_sign_put_url + '?s3_object_type=' + file.type + '&s3_object_name=' + encodeURIComponent(file.name), true

		# Hack to pass bytes through unprocessed.
		xhr.overrideMimeType 'text/plain; charset=x-user-defined'

		xhr.onreadystatechange = (e) ->
			if this.readyState == 4 and this.status == 200
				try
					result = JSON.parse this.responseText
				catch error
					this_s3upload.onError 'Signing server returned some ugly/empty JSON: "' + this.responseText + '"'
					return false
				callback result.signed_request, result.url
			else if this.readyState == 4 and this.status != 200
				this_s3upload.onError 'Could not contact request signing server. Status = ' + this.status
		xhr.send()

	# Use a CORS call to upload the given file to S3. Assumes the url
	# parameter has been signed and is accessible for upload.
	uploadToS3: (file, url, public_url) ->
		this_s3upload = this

		xhr = @createCORSRequest 'PUT', url
		if !xhr
			@onError 'CORS not supported'
		else
			xhr.onload = ->
				if xhr.status == 200
					this_s3upload.onProgress 100, 'Upload completed.', public_url, file
					this_s3upload.onFinishS3Put public_url, file
				else
					this_s3upload.onError 'Upload error: ' + xhr.status, file

			xhr.onerror = ->
				this_s3upload.onError 'XHR error.', file

			xhr.upload.onprogress = (e) ->
				if e.lengthComputable
					percentLoaded = Math.round (e.loaded / e.total) * 100
					this_s3upload.onProgress percentLoaded, (if percentLoaded == 100 then 'Finalizing.' else 'Uploading.'), public_url, file

		xhr.setRequestHeader 'Content-Type', file.type
		xhr.setRequestHeader 'x-amz-acl', 'public-read'

		xhr.send file

	validate: (file) ->
		# should be overridden and return an error message (string)
		# or a falsey value in case the validation passes
		null

	uploadFile: (file) ->
		error = @validate file
		if error
			@onError error, file
			return null

		this_s3upload = this
		@executeOnSignedUrl file, (signedURL, publicURL) ->
			this_s3upload.uploadToS3 file, signedURL, publicURL
