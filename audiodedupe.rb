# Audio De-duper

# This script takes multiple directories as input, and tells you which files inside those directories contain duplicate audio data.
# For a variety of reasons, it is possible to have files that produce different cryptographic hashes, but contain the same acoustic data.
# This can happen if dumb programs inadvertently write to ID3 data, or the ID3 data is intentionally changed to correct something
# like album art. It can also happen when transcoding between lossless formats.

# Only files that have the exact same waveform data are considered duplicates. Other perceptual hashing programs can find similar sounding
# files. We don't care about similar sounding, or things like "this was cropped from a larger file". We only care about 100% identical
# files, where only the metadata differs.

# A reference folder is one where files inside should never be deleted, even if there are duplicates located within that folder. Only
# duplicate files where one copy exists outside of a reference folder (and one copy within a reference folder) will ever be deleted.

# If you want to find files duplicated in reference folders, you can find duplicate DB rows manually - however, we can't pick one at
# random and delete one, because both folders are marked as being of the same importance.

# Add folders to the hash below, using the format:
# '/folder/path/' => is_reference,
# E.g. '/Temp/Music/' => true

search_paths = {
  '/home/kyon/music/' => true,
  '/home/kyon/dupes/' => false
}

# What file types are we looking for duplicates in? Everything else will be ignored.

supported_file_types = ['FLAC', 'MP3']

# Should we actually iterate over the filesystem, or just skip to the results from the last run 

should_scan_files = true

# Should we actually delete any data, or just tell you what to delete?

should_delete_files = true

###

require 'pg'
require 'active_record'
require 'digest'
require 'fileutils'

ActiveRecord::Base.establish_connection(
  "postgres://postgres@localhost/audiodedupe"
)

class Song < ActiveRecord::Base
  self.table_name = "songs"
end

if should_scan_files
  # Scan through all files and create DB entries for them
  search_paths.each do |search_path, is_reference|
    puts search_path
    Dir.glob(search_path + '**/*') do |filename|
      next if filename == '.' or filename == '..'
  
      # Ignore:
      file_extension = filename.split('/')[-1].split('.')[-1]
      next if !supported_file_types.include?(file_extension.upcase)
  
      puts filename
  
      if Song.where(path: filename).first.nil?
        command = "ffmpeg -i \"#{filename}\" -map_metadata:g -1 -c:a pcm_s16le out.wav"
        puts command
        `#{command}`
  
        perceptual_hash = `shasum -a 256 out.wav`
        perceptual_hash = perceptual_hash[0..63]
        puts perceptual_hash
        
        Song.create(path: filename, is_reference: is_reference, perceptual_hash: perceptual_hash)
        `rm out.wav`
      end
    end
  end
end

Song.where(is_reference: true).find_each do |song|
  Song.where(perceptual_hash: song.perceptual_hash, is_reference: false).find_each do |duplicate_song|
    if !should_delete_files
      puts "You can delete duplicate #{duplicate_song.path} - it's a duplicate of #{song.path}"
    else
      duplicate_song.destroy!
      File.delete(duplicate_song.path) if File.exist?(duplicate_song.path)
      puts "Removed #{duplicate_song.path}"
    end
  end
end

puts ""
puts "Duplicate Reference Songs:"
puts "---------------------------"
Song.where(is_reference: true).find_each do |song|
  Song.where(perceptual_hash: song.perceptual_hash, is_reference: true).find_each do |duplicate_song|
    if duplicate_song.id != song.id
      puts "  #{duplicate_song.path} == #{song.path}"
    end
  end
end
