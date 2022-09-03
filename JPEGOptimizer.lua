--[[
Copyright (c) 2018 Flavio Tischhauser <ftischhauser@gmail.com>
https://github.com/ftischhauser/JPEGOptimizer

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
--]]

local LrView = import 'LrView'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local LrHttp = import 'LrHttp'
local LrColor = import 'LrColor'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import'LrFileUtils'
local LrLogger = import 'LrLogger'

local logger = LrLogger('JPEGOptimizer')
logger:enable("logfile")

quote4Win = function (cmd)
	if (WIN_ENV) then return '"' .. cmd .. '"' else return cmd end
end

outputToLog = function (msg)
	logger:trace(msg)  -- Uncomment this line to enable logging
end

-- Define paths for external tools
local UPexiv2 = 'exiv2'
local UPImageMagick = 'ImageMagick'
local UPjpegrecompress = 'jpeg-archive'
local UPjpegtran = 'mozjpeg'
local UPcjpeg = 'mozjpeg'
local UPcjxl = 'jxl'

-- Define executable names for external tools
local UEexiv2 = 'exiv2' .. (WIN_ENV and '.exe' or '')
local UEImageMagick = MAC_ENV and 'convert' or 'magick.exe'
local UEjpegrecompress = 'jpeg-recompress' .. (WIN_ENV and '.exe' or '')
local UEjpegtran = 'jpegtran' .. (WIN_ENV and '.exe' or '')
local UEcjpeg = 'cjpeg' .. (WIN_ENV and '.exe' or '')
local UEcjxl = 'cjxl' .. (WIN_ENV and '.exe' or '')

-- Define platform-specific path for external tools
local PlatPath = MAC_ENV and 'macOS' or 'WIN'
-- Construct commands for external tools (reusing path variables)
if MAC_ENV then
	local ExivPath = LrPathUtils.child(LrPathUtils.child(_PLUGIN.path, PlatPath), UPexiv2)
	UPexiv2 = 'LD_LIBRARY_PATH="' .. ExivPath .. '" "' .. LrPathUtils.child(ExivPath, UEexiv2) .. '"'
else
	UPexiv2 = '"' .. LrPathUtils.child(LrPathUtils.child(LrPathUtils.child(_PLUGIN.path, PlatPath), UPexiv2), UEexiv2) .. '"'
end
UPImageMagick = '"' .. LrPathUtils.child(LrPathUtils.child(LrPathUtils.child(_PLUGIN.path, PlatPath), UPImageMagick), UEImageMagick) .. '"'
UPjpegrecompress = '"' .. LrPathUtils.child(LrPathUtils.child(LrPathUtils.child(_PLUGIN.path, PlatPath), UPjpegrecompress), UEjpegrecompress) .. '"'
UPjpegtran = '"' .. LrPathUtils.child(LrPathUtils.child(LrPathUtils.child(_PLUGIN.path, PlatPath), UPjpegtran), UEjpegtran) .. '"'
UPcjpeg = '"' .. LrPathUtils.child(LrPathUtils.child(LrPathUtils.child(_PLUGIN.path, PlatPath), UPcjpeg), UEcjpeg) .. '"'
UPcjxl = '"' .. LrPathUtils.child(LrPathUtils.child(LrPathUtils.child(_PLUGIN.path, PlatPath), UPcjxl), UEcjxl) .. '"'

ObserveFTJO_RemovePreview = function (propertyTable)
	if(propertyTable.FTJO_RemovePreview) then propertyTable.FTJO_StripMetadata = false end
end
ObserveFTJO_StripMetadata = function (propertyTable)
	if(propertyTable.FTJO_StripMetadata) then propertyTable.FTJO_RemovePreview = false end
end
ObserveMOZJ_Recompress = function (propertyTable)
	if(propertyTable.MOZJ_Recompress) then
		propertyTable.FTJO_Recompress = false
		propertyTable.JPEGXL_Recompress = false
	end
end
ObserveFTJO_Recompress = function (propertyTable)
	if(propertyTable.FTJO_Recompress) then
		propertyTable.JPEGXL_Recompress = false
		propertyTable.MOZJ_Recompress = false
	end
end
ObserveJPEGXL_Recompress = function (propertyTable)
	if(propertyTable.JPEGXL_Recompress) then
		propertyTable.FTJO_Recompress = false
		propertyTable.MOZJ_Recompress = false
	end
end

RecompressFile = function (functionContext, filterContext, sourceRendition, renditionToSatisfy)
	local success, pathOrMessage = sourceRendition:waitForRender()
	if success then

    if LrTasks.execute(UEImageMagick .. ' -version') == 0 then
      UPImageMagick = UEImageMagick
    end

		if renditionToSatisfy.recompress then
			local renderFileName = LrPathUtils.standardizePath(pathOrMessage) -- Rendered file
			local ExpFileName = LrPathUtils.standardizePath(renditionToSatisfy.destinationPath) -- Final exported file
			outputToLog('')
			outputToLog('Lightroom render: ' .. renderFileName)
      local InFileAttr =  LrFileUtils.fileAttributes(renderFileName)
      if InFileAttr['fileSize'] ~= nil then
        outputToLog('  ' .. renderFileName .. ': ' .. InFileAttr['fileSize'])
      end

			if filterContext.propertyTable.JPEGXL_Recompress then
				local CmdRecompress = UPcjxl .. ' "' .. renderFileName .. '" "' .. ExpFileName .. '" -q 90 -e 9'
				if filterContext.propertyTable.FTJO_Progressive then CmdRecompress = CmdRecompress .. ' -p' end
				outputToLog('Recompress: ' .. CmdRecompress)
				if LrTasks.execute(quote4Win(CmdRecompress)) ~= 0 then
					renditionToSatisfy:renditionIsDone(false, 'Error recompressing JPEG XL file: ' .. CmdRecompress)
					LrFileUtils.delete(renderFileName)
					LrFileUtils.delete(ExpFileName)
					return false
				end
				LrFileUtils.delete(renderFileName)
			elseif filterContext.propertyTable.MOZJ_Recompress then
				if not filterContext.propertyTable.FTJO_StripMetadata then
					local CmdDumpMetadata = UPexiv2 .. ' -q -f -eX "' .. renderFileName .. '"'
					outputToLog('Dump metadata: ' .. CmdDumpMetadata)
					if LrTasks.execute(quote4Win(CmdDumpMetadata)) ~= 0 then
						renditionToSatisfy:renditionIsDone(false, 'Error exporting XMP data.')
						LrFileUtils.delete(renderFileName)
						LrFileUtils.delete(LrPathUtils.replaceExtension(renderFileName, 'xmp'))
						return false
					end
					LrFileUtils.move(LrPathUtils.replaceExtension(renderFileName, 'xmp'), LrPathUtils.replaceExtension(ExpFileName, 'xmp'))

					if not filterContext.propertyTable.FTJO_RemovePreview then
						local CmdRenderPreview = UPImageMagick .. ' "' .. renderFileName .. '" -resize 256x256 ppm:- | ' .. UPjpegrecompress .. ' --quiet --no-progressive --method smallfry --quality low --strip --ppm - "' .. LrPathUtils.removeExtension(ExpFileName) .. '-thumb.jpg"'
						outputToLog('Render preview: ' .. CmdRenderPreview)
						if LrTasks.execute(quote4Win(CmdRenderPreview)) ~= 0 then
							renditionToSatisfy:renditionIsDone(false, 'Error creating EXIF thumbnail.')
							LrFileUtils.delete(renderFileName)
							LrFileUtils.delete(LrPathUtils.replaceExtension(ExpFileName, 'xmp'))
							LrFileUtils.delete(LrPathUtils.removeExtension(ExpFileName) ..'-thumb.jpg')
							return false
						end
					end
				end

        if filterContext.propertyTable.MOZJ_UseTIFF then
          local CmdCreatePNG = UPImageMagick .. ' convert "' .. renderFileName .. '" -define png:compression-level=0 -define png:compression-filter=0 -define png:compression-strategy=0 -colorspace sRGB "' .. renderFileName .. '.png"'
          outputToLog('-> PNG: ' .. CmdCreatePNG)
          if LrTasks.execute(quote4Win(CmdCreatePNG)) ~= 0 then
            renditionToSatisfy:renditionIsDone(false, 'Error converting TIFF to PNG file.')
            LrFileUtils.delete(renderFileName)
            LrFileUtils.delete(renderFileName .. '.png')
            LrFileUtils.delete(LrPathUtils.replaceExtension(ExpFileName, 'xmp'))
            LrFileUtils.delete(LrPathUtils.removeExtension(ExpFileName) ..'-thumb.jpg')
            return false
          end
          local PNGAttr =  LrFileUtils.fileAttributes(renderFileName .. '.png')
          if PNGAttr['fileSize'] ~= nil then
            outputToLog('  ' .. renderFileName .. '.png: ' .. PNGAttr['fileSize'])
          end
          LrFileUtils.delete(renderFileName)
          renderFileName = renderFileName .. '.png'
        end

				local CmdRecompress = UPcjpeg .. ' -outfile "' .. ExpFileName .. '"'
				if not filterContext.propertyTable.FTJO_Progressive then CmdRecompress = CmdRecompress .. ' -baseline' end
				CmdRecompress = CmdRecompress .. ' "' .. renderFileName
				outputToLog('-> JPEG: ' .. CmdRecompress)
				if LrTasks.execute(quote4Win(CmdRecompress)) ~= 0 then
					renditionToSatisfy:renditionIsDone(false, 'Error creating MozJPEG JPEG file from PNG.')
          LrFileUtils.delete(renderFileName)
					LrFileUtils.delete(ExpFileName)
					LrFileUtils.delete(LrPathUtils.replaceExtension(ExpFileName, 'xmp'))
					LrFileUtils.delete(LrPathUtils.removeExtension(ExpFileName) ..'-thumb.jpg')
					return false
				end
				LrFileUtils.delete(renderFileName)

				if not filterContext.propertyTable.FTJO_StripMetadata then
					local CmdInsertMetadata = UPexiv2 .. ' -q -f -iX "' .. ExpFileName .. '"' .. (MAC_ENV and ' 2>/dev/null' or ' 2>nul')
					outputToLog('Insert metadata: ' .. CmdInsertMetadata)
					if LrTasks.execute(quote4Win(CmdInsertMetadata)) ~= 0 then
						renditionToSatisfy:renditionIsDone(false, 'Error importing XMP data.')
						LrFileUtils.delete(ExpFileName)
						LrFileUtils.delete(LrPathUtils.replaceExtension(ExpFileName, 'xmp'))
						LrFileUtils.delete(LrPathUtils.removeExtension(ExpFileName) ..'-thumb.jpg')
						return false
					end
					LrFileUtils.delete(LrPathUtils.replaceExtension(ExpFileName, 'xmp'))

					if not filterContext.propertyTable.FTJO_RemovePreview then
						local CmdInsertPreview = UPexiv2 .. ' -q -f -it "' .. ExpFileName .. '"'
						outputToLog('Insert preview: ' .. CmdInsertPreview)
						if LrTasks.execute(quote4Win(CmdInsertPreview)) ~= 0 then
							renditionToSatisfy:renditionIsDone(false, 'Error importing EXIF thumbnail.')
							LrFileUtils.delete(ExpFileName)
							LrFileUtils.delete(LrPathUtils.removeExtension(ExpFileName) ..'-thumb.jpg')
							return false
						end
						LrFileUtils.delete(LrPathUtils.removeExtension(ExpFileName) ..'-thumb.jpg')
					end
				end
				LrFileUtils.delete(renderFileName)
        local ExpAttr =  LrFileUtils.fileAttributes(ExpFileName)
        if ExpAttr['fileSize'] ~= nil then
          outputToLog('  ' .. ExpFileName .. ': ' .. ExpAttr['fileSize'])
        end
			elseif filterContext.propertyTable.FTJO_Recompress then
				if not filterContext.propertyTable.FTJO_StripMetadata then
					local CmdDumpMetadata = UPexiv2 .. ' -q -f -eX "' .. renderFileName .. '"'
					outputToLog('Dump metadata: ' .. CmdDumpMetadata)
					if LrTasks.execute(quote4Win(CmdDumpMetadata)) ~= 0 then
						renditionToSatisfy:renditionIsDone(false, 'Error exporting XMP data.')
						LrFileUtils.delete(renderFileName)
						LrFileUtils.delete(LrPathUtils.replaceExtension(renderFileName, 'xmp'))
						return false
					end
					LrFileUtils.move(LrPathUtils.replaceExtension(renderFileName, 'xmp'), LrPathUtils.replaceExtension(ExpFileName, 'xmp'))
					if not filterContext.propertyTable.FTJO_RemovePreview then
						local CmdRenderPreview = UPImageMagick .. ' "' .. renderFileName .. '" -resize 256x256 ppm:- | ' .. UPjpegrecompress .. ' --quiet --no-progressive --method smallfry --quality low --strip --ppm - "' .. LrPathUtils.removeExtension(ExpFileName) .. '-thumb.jpg"'
						outputToLog('Render preview: ' .. CmdRenderPreview)
						if LrTasks.execute(quote4Win(CmdRenderPreview)) ~= 0 then
							renditionToSatisfy:renditionIsDone(false, 'Error creating EXIF thumbnail.')
							LrFileUtils.delete(renderFileName)
							LrFileUtils.delete(LrPathUtils.replaceExtension(ExpFileName, 'xmp'))
							LrFileUtils.delete(LrPathUtils.removeExtension(ExpFileName) ..'-thumb.jpg')
							return false
						end
					end
				end

				local CmdRecompress = UPImageMagick .. ' "' .. renderFileName .. '" ppm:- | ' .. UPjpegrecompress .. ' --quiet --accurate --method ' .. filterContext.propertyTable.FTJO_JRCMethod .. ' --quality ' .. filterContext.propertyTable.FTJO_JRCQuality .. ' --strip'
				if not filterContext.propertyTable.FTJO_Progressive then CmdRecompress = CmdRecompress .. ' --no-progressive' end
				if not filterContext.propertyTable.FTJO_JRCSubsampling then CmdRecompress = CmdRecompress .. ' --subsample disable' end
				CmdRecompress = CmdRecompress .. ' --ppm - "' .. ExpFileName ..  '"'
				outputToLog('Recompress: ' .. CmdRecompress)
				if LrTasks.execute(quote4Win(CmdRecompress)) ~= 0 then
					renditionToSatisfy:renditionIsDone(false, 'Error recompressing JPEG file.')
					LrFileUtils.delete(renderFileName)
					LrFileUtils.delete(ExpFileName)
					LrFileUtils.delete(LrPathUtils.replaceExtension(ExpFileName, 'xmp'))
					LrFileUtils.delete(LrPathUtils.removeExtension(ExpFileName) ..'-thumb.jpg')
					return false
				end
				LrFileUtils.delete(renderFileName)

				if not filterContext.propertyTable.FTJO_StripMetadata then
					local CmdInsertMetadata = UPexiv2 .. ' -q -f -iX "' .. ExpFileName .. '"' .. (MAC_ENV and ' 2>/dev/null' or ' 2>nul')
					outputToLog('Insert metadata: ' .. CmdInsertMetadata)
					if LrTasks.execute(quote4Win(CmdInsertMetadata)) ~= 0 then
						renditionToSatisfy:renditionIsDone(false, 'Error importing XMP data.')
						LrFileUtils.delete(ExpFileName)
						LrFileUtils.delete(LrPathUtils.replaceExtension(ExpFileName, 'xmp'))
						LrFileUtils.delete(LrPathUtils.removeExtension(ExpFileName) ..'-thumb.jpg')
						return false
					end
					LrFileUtils.delete(LrPathUtils.replaceExtension(ExpFileName, 'xmp'))

					if not filterContext.propertyTable.FTJO_RemovePreview then
						local CmdInsertPreview = UPexiv2 .. ' -q -f -it "' .. ExpFileName .. '"'
						outputToLog('Insert preview: ' .. CmdInsertPreview)
						if LrTasks.execute(quote4Win(CmdInsertPreview)) ~= 0 then
							renditionToSatisfy:renditionIsDone(false, 'Error importing EXIF thumbnail.')
							LrFileUtils.delete(ExpFileName)
							LrFileUtils.delete(LrPathUtils.removeExtension(ExpFileName) ..'-thumb.jpg')
							return false
						end
						LrFileUtils.delete(LrPathUtils.removeExtension(ExpFileName) ..'-thumb.jpg')
					end
				end
				LrFileUtils.delete(renderFileName)
			end
		else
			outputToLog('Not recompressing file: ' .. pathOrMessage)
			if filterContext.propertyTable.LR_format ~= 'JPEG' then
				if filterContext.propertyTable.FTJO_RemovePreview and not filterContext.propertyTable.FTJO_StripMetadata then
					local CmdRemovePreview = UPexiv2 .. ' -q -f -dt "' .. ExpFileName .. '"'
					outputToLog('Remove preview: ' .. CmdRemovePreview)
					if LrTasks.execute(quote4Win(CmdRemovePreview)) ~= 0 then
						renditionToSatisfy:renditionIsDone(false, 'Error removing EXIF thumbnail.')
						LrFileUtils.delete(ExpFileName)
						return false
					end
				end

				local CmdOptimize = filterContext.propertyTable.FTJO_StripMetadata and UPjpegtran .. ' -copy none' or UPjpegtran .. ' -copy all'
				if not filterContext.propertyTable.FTJO_Progressive then CmdOptimize = CmdOptimize .. ' -revert -optimize' end
				CmdOptimize = CmdOptimize .. ' -outfile "' .. ExpFileName .. '" "' .. ExpFileName .. '"'
				outputToLog('Optimize: ' .. CmdOptimize)
				if LrTasks.execute(quote4Win(CmdOptimize)) ~= 0 then
					renditionToSatisfy:renditionIsDone(false, 'Error optimizing JPEG file.')
					LrFileUtils.delete(ExpFileName)
					return false
				end
			end
		end
    renditionToSatisfy:renditionIsDone(true)
	else
		renditionToSatisfy:renditionIsDone(false, pathOrMessage)
		return false
	end
	
	return true
end

return {
	exportPresetFields = {
		{key = 'FTJO_RemovePreview', default = true},
		{key = 'FTJO_StripMetadata', default = false},
		{key = 'FTJO_Progressive', default = true},
		{key = 'FTJO_Recompress', default = false},
		{key = 'FTJO_JRCQuality', default = 'medium'},
		{key = 'FTJO_JRCMethod', default = 'smallfry'},
		{key = 'FTJO_JRCSubsampling', default = true},
		{key = 'JPEGXL_Recompress', default = false},
		{key = 'MOZJ_Recompress', default = false},
		{key = 'MOZJ_UseTIFF', default = false}
	},
	sectionForFilterInDialog = function(viewFactory, propertyTable)
		propertyTable:addObserver('FTJO_RemovePreview', ObserveFTJO_RemovePreview)
		propertyTable:addObserver('FTJO_StripMetadata', ObserveFTJO_StripMetadata)
		propertyTable:addObserver('JPEGXL_Recompress', ObserveJPEGXL_Recompress)
		propertyTable:addObserver('MOZJ_Recompress', ObserveMOZJ_Recompress)
		propertyTable:addObserver('FTJO_Recompress', ObserveFTJO_Recompress)
		return {
			title = 'JPEG Optimizer',
			viewFactory:column {
				spacing = viewFactory:control_spacing(),
				viewFactory:column {
					viewFactory:static_text {title = 'Please visit the homepage for help with these options:'},
					viewFactory:static_text {
						title = 'http://github.com/ftischhauser/JPEGOptimizer',
						mouse_down = function() LrHttp.openUrlInBrowser('http://github.com/ftischhauser/JPEGOptimizer') end,
						text_color = LrColor( 0, 0, 1 )
					},
					viewFactory:spacer {height = 10},
					viewFactory:group_box {
						title = 'Lossless Optimizations',
						viewFactory:checkbox {
							title = 'Remove EXIF thumbnail',
							value = LrView.bind 'FTJO_RemovePreview',
							checked_value = true,
							unchecked_value = false
						},
						viewFactory:checkbox {
							title = 'Strip ALL metadata (including thumbnail)',
							value = LrView.bind 'FTJO_StripMetadata',
							checked_value = true,
							unchecked_value = false
						},
						viewFactory:checkbox {
							title = 'Progressive encoding (smaller)',
							value = LrView.bind 'FTJO_Progressive',
							checked_value = true,
							unchecked_value = false
						},
						viewFactory:column {
							viewFactory:static_text {
								title = 'Powered by mozjpeg and exiv2:'
							},
							viewFactory:static_text {
								title = 'https://github.com/mozilla/mozjpeg/',
								mouse_down = function() LrHttp.openUrlInBrowser('https://github.com/mozilla/mozjpeg/') end,
								text_color = LrColor( 0, 0, 1 )
							},
							viewFactory:static_text {
								title = 'http://www.exiv2.org/',
								mouse_down = function() LrHttp.openUrlInBrowser('http://www.exiv2.org/') end,
								text_color = LrColor( 0, 0, 1 )
							}
						}
					},
					viewFactory:group_box {
						title = 'JPEG XL Recompression',
						viewFactory:checkbox {
							title = 'Recompress JPEG',
							value = LrView.bind 'JPEGXL_Recompress',
							checked_value = true,
							unchecked_value = false,
						},
					},
					viewFactory:group_box {
						title = 'MozJPEG Recompression',
						viewFactory:checkbox {
							title = 'Recompress JPEG',
							value = LrView.bind 'MOZJ_Recompress',
							checked_value = true,
							unchecked_value = false,
						},
						viewFactory:checkbox {
							value = LrView.bind 'MOZJ_Recompress',
							title = 'Use TIFF',
							value = LrView.bind 'MOZJ_UseTIFF',
							checked_value = true,
							unchecked_value = false,
						},
					},
					viewFactory:group_box {
						title = 'Recompression',
						viewFactory:checkbox {
							title = 'Recompress JPEG',
							value = LrView.bind 'FTJO_Recompress',
							checked_value = true,
							unchecked_value = false,
						},
						viewFactory:static_text {
							enabled = LrView.bind 'FTJO_Recompress',
							title = "Automatically sets the optimal JPEG compression by measuring the perceived visual quality."
						},
						viewFactory:checkbox {
							enabled = LrView.bind 'FTJO_Recompress',
							title = 'Chroma subsampling (smaller)',
							value = LrView.bind 'FTJO_JRCSubsampling',
							checked_value = true,
							unchecked_value = false,
						},
						viewFactory:row {
							viewFactory:static_text {
								enabled = LrView.bind 'FTJO_Recompress',
								title = "Quality:",
								width = LrView.share "FTJO_Recompress_label_width",
							},
							viewFactory:popup_menu {
								enabled = LrView.bind 'FTJO_Recompress',
								value = LrView.bind 'FTJO_JRCQuality',
								width = LrView.share "FTJO_Recompress_popup_width",
								items = {
									{ title = "Low", value = 'low'},
									{ title = "Medium", value = 'medium'},
									{ title = "High", value = 'high'},
									{ title = "Very High", value = 'veryhigh'}
								}
							}
						},
						viewFactory:row {
							viewFactory:static_text {
								enabled = LrView.bind 'FTJO_Recompress',
								title = "Method:",
								width = LrView.share "FTJO_Recompress_label_width",
							},
							viewFactory:popup_menu {
								enabled = LrView.bind 'FTJO_Recompress',
								value = LrView.bind 'FTJO_JRCMethod',
								width = LrView.share "FTJO_Recompress_popup_width",
								items = {
									{ title = "MPE", value = 'mpe'},
									{ title = "SSIM", value = 'ssim'},
									{ title = "MS-SSIM", value = 'ms-ssim'},
									{ title = "SmallFry", value = 'smallfry'}
								}
							}
						},
						viewFactory:column {
							viewFactory:static_text {
								title = 'Powered by jpeg-archive and ImageMagick:',
								enabled = LrView.bind 'FTJO_Recompress',
							},
							viewFactory:static_text {
								enabled = LrView.bind 'FTJO_Recompress',
								title = 'https://github.com/danielgtaylor/jpeg-archive/',
								mouse_down = function() LrHttp.openUrlInBrowser('https://github.com/danielgtaylor/jpeg-archive/') end,
								text_color = LrColor( 0, 0, 1 )
							},
							viewFactory:static_text {
								enabled = LrView.bind 'FTJO_Recompress',
								title = 'https://www.imagemagick.org/',
								mouse_down = function() LrHttp.openUrlInBrowser('https://www.imagemagick.org/') end,
								text_color = LrColor( 0, 0, 1 )
							}
						}
					}
				}
			}
		}
	end,
	postProcessRenderedPhotos = function(functionContext, filterContext)
		local renditionOptions = {
			filterSettings = function( renditionToSatisfy, exportSettings )
				outputToLog('Final output file: ' .. renditionToSatisfy.destinationPath)
				renditionToSatisfy.recompress = false

				if renditionToSatisfy.destinationPath:match('\.[Jj][Pp][Gg]$') then
					if filterContext.propertyTable.JPEGXL_Recompress then
						outputToLog('Rendering PNG sRGB 16bpp for JPEG XL')
						renditionToSatisfy.recompress = true
						exportSettings.LR_format = 'PNG'
						exportSettings.LR_export_colorSpace = 'sRGB'
						exportSettings.LR_export_bitDepth = 16
						return LrPathUtils.removeExtension(renditionToSatisfy.destinationPath) .. '-' .. os.time() .. '-JPEGXL.png'
					elseif filterContext.propertyTable.FTJO_Recompress then
						outputToLog('Rendering TIFF sRGB 8bpp')
						renditionToSatisfy.recompress = true
						exportSettings.LR_format = 'TIFF'
						exportSettings.LR_export_colorSpace = 'sRGB'
						exportSettings.LR_export_bitDepth = 8
            exportSettings.LR_tiff_compressionMethod = 'compressionMethod_None'
						return LrPathUtils.removeExtension(renditionToSatisfy.destinationPath) .. '-' .. os.time() .. '-FTJO.tif'
					elseif filterContext.propertyTable.MOZJ_Recompress then
						renditionToSatisfy.recompress = true
            if filterContext.propertyTable.MOZJ_UseTIFF then
              outputToLog('Rendering TIFF sRGB 8bpp for MozJPEG')
              exportSettings.LR_format = 'TIFF'
              exportSettings.LR_export_colorSpace = 'sRGB'
              exportSettings.LR_export_bitDepth = 8
              exportSettings.LR_tiff_compressionMethod = 'compressionMethod_None'
              return LrPathUtils.removeExtension(renditionToSatisfy.destinationPath) .. '-' .. os.time() .. '-MOZJ.tif'
            else
              outputToLog('Rendering JPEG sRGB 8bpp for MozJPEG')
              exportSettings.LR_format = 'JPEG'
              exportSettings.LR_export_colorSpace = 'sRGB'
              exportSettings.LR_export_bitDepth = 8
              exportSettings.LR_jpeg_quality = 1
              exportSettings.LR_jpeg_useLimitSize = false
              return LrPathUtils.removeExtension(renditionToSatisfy.destinationPath) .. '-' .. os.time() .. '-MOZJ.jpg'
            end
					else
						outputToLog('Not modifying rendering, recompression not selected')
					end
				else
					outputToLog('Not modifying rendering, output isn\'t JPEG')
				end
			end,
		}

		for sourceRendition, renditionToSatisfy in filterContext:renditions(renditionOptions) do
			if RecompressFile(functionContext, filterContext, sourceRendition, renditionToSatisfy) then
				outputToLog('Successfully exported file: ' .. renditionToSatisfy.destinationPath)
			else
				outputToLog('Failed exporting file: ' .. renditionToSatisfy.destinationPath)
			end
		end
	end
}
