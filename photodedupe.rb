# Photo De-duper

# This script takes multiple directories as input, and tells you which images inside those directories contain duplicate image data.
# For a variety of reasons, it is possible to have files that produce different cryptographic hashes, but contain the same pixel data.
# This can happen if dumb programs inadvertently write to EXIF data, or the EXIF data is intentionally changed to correct something
# like clock drift or timezone offsets. It can also happen when transcoding between lossless formats, e.g. BMP -> PNG.

# Only photos that have the exact same pixel data are considered duplicates. Other perceptual hashing programs can find similar looking
# images. We don't care about similar looking, or things like "this was cropped from a larger image". We only care about 100% identical
# images, where only the metadata differs.

# A reference folder is one where files inside should never be deleted, even if there are duplicates located within that folder. Only
# duplicate files where one copy exists outside of a reference folder (and one copy within a reference folder) will ever be deleted.

# If you want to find files duplicated in reference folders, you can find duplicate DB rows manually - however, we can't pick one at
# random and delete one, because both folders are marked as being of the same importance.

# Add folders to the hash below, using the format:
# '/folder/path/' => is_reference,
# E.g. '/Temp/Photos/' => true

search_paths = {
  '/home/kyon/photos/' => true,
  '/home/kyon/random/' => false
}

# What file types are we looking for duplicates in? Everything else will be ignored.

supported_file_types = ['JPEG', 'JPG', 'PNG', 'BMP', 'CR2', 'DNG', 'TIF']

# Should we actually iterate over the filesystem, or just skip to the results from the last run 

should_scan_files = true

# Should we actually delete any data, or just tell you what to delete?

should_delete_files = true

###

require 'pg'
require 'active_record'
require 'digest'
require 'fileutils'
require 'parallel'

ActiveRecord::Base.establish_connection(
  "postgres://postgres@localhost/photodedupe"
)

def sha256(file)
  hash = File.open(file, 'rb') do |io|
    dig = Digest::SHA2.new(256)
    buf = ""
    dig.update(buf) while io.read(4096, buf)
    dig
  end
  return hash.hexdigest
end

class Image < ActiveRecord::Base
  self.table_name = "images"
end

if should_scan_files
  # Scan through all files and create DB entries for them
  search_paths.each do |search_path, is_reference|
    puts search_path
    files = Dir.glob(search_path + '**/*')
    Parallel.each(files, in_processes: 4) do |filename|
      next if filename == '.' or filename == '..'
      # Ignore:
      file_extension = filename.split('/')[-1].split('.')[-1]
      next if !supported_file_types.include?(file_extension.upcase)
  
      puts filename
      temp = SecureRandom.uuid  

      if Image.where(path: filename).first.nil?
        File.delete("#{temp}.mpc") if File.exist?("#{temp}.mpc")
        File.delete("#{temp}.cache") if File.exist?("#{temp}.cache")

        command = "convert \"#{filename}\" \"#{temp}.mpc\""
        puts command
        `#{command}`
  
        pwd = Dir.pwd
        
        begin
          perceptual_hash = sha256("#{pwd}/#{temp}.cache")
          puts perceptual_hash
          if perceptual_hash.length == 64
            Image.create(path: filename, is_reference: is_reference, perceptual_hash: perceptual_hash)
          else
            raise PerceptualHashError
          end

          File.delete("#{temp}.mpc") if File.exist?("#{temp}.mpc")
          File.delete("#{temp}.cache") if File.exist?("#{temp}.cache")
        rescue => e
          puts "Problem handling #{filename}"
        end

      end
    end
  end
end

Image.where(is_reference: true).find_each do |image|
  Image.where(perceptual_hash: image.perceptual_hash, is_reference: false).find_each do |duplicate_image|
    if !should_delete_files
      puts "You can delete duplicate #{duplicate_image.path} - it's a duplicate of #{image.path}"
    else
      duplicate_image.destroy!
      File.delete(duplicate_image.path) if File.exist?(duplicate_image.path)
      puts "Removed #{duplicate_image.path}"
    end
  end
end

puts ""
puts "Duplicate Reference Images:"
puts "---------------------------"
Image.where(is_reference: true).find_each do |image|
  Image.where(perceptual_hash: image.perceptual_hash, is_reference: true).find_each do |duplicate_image|
    if duplicate_image.id != image.id
      puts "  #{duplicate_image.path} == #{image.path}"
    end
  end
end
