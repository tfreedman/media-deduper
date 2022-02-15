# media-deduper
De-duplicate music and images that are visually or acoustically 100% identical, even if the associated metadata in the file or the file format itself is different. Useful when transcoding files losslessly from one format to another, or when intentionally editing things like EXIF or ID3 tags. Existing code relies on PostgreSQL via ActiveRecord, but this can be swapped trivially for a different database engine. Requires ImageMagick or ffmpeg, depending on which script you run.

## Table Structure

```
songs or images = {path: text, perceptual_hash: text, is_reference: boolean}
```

## Photo De-duper

This script takes multiple directories as input, and tells you which images inside those directories contain duplicate image data. For a variety of reasons, it is possible to have files that produce different cryptographic hashes, but contain the same pixel data. This can happen if dumb programs inadvertently write to EXIF data, or the EXIF data is intentionally changed to correct something like clock drift or timezone offsets. It can also happen when transcoding between lossless formats, e.g. BMP -> PNG.

Only photos that have the exact same pixel data are considered duplicates. Other perceptual hashing programs can find similar looking images. We don't care about similar looking, or things like "this was cropped from a larger image". We only care about 100% identical images, where only the metadata differs.

A reference folder is one where files inside should never be deleted, even if there are duplicates located within that folder. Only duplicate files where one copy exists outside of a reference folder (and one copy within a reference folder) will ever be deleted.

If you want to find files duplicated in reference folders, you can find duplicate DB rows manually - however, we can't pick one at random and delete one, because both folders are marked as being of the same importance.

## Audio De-duper

This script takes multiple directories as input, and tells you which files inside those directories contain duplicate audio data. For a variety of reasons, it is possible to have files that produce different cryptographic hashes, but contain the same acoustic data. This can happen if dumb programs inadvertently write to ID3 data, or the ID3 data is intentionally changed to correct something like album art. It can also happen when transcoding between lossless formats, e.g. WAV -> FLAC

Only files that have the exact same waveform data are considered duplicates. Other perceptual hashing programs can find similar sounding files. We don't care about similar sounding, or things like "this was cropped from a larger file". We only care about 100% identical files, where only the metadata differs.

A reference folder is one where files inside should never be deleted, even if there are duplicates located within that folder. Only duplicate files where one copy exists outside of a reference folder (and one copy within a reference folder) will ever be deleted.

If you want to find files duplicated in reference folders, you can find duplicate DB rows manually - however, we can't pick one at random and delete one, because both folders are marked as being of the same importance.
