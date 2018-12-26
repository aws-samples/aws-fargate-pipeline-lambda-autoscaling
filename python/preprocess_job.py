import os, sys
try:
    from PIL import Image
except ImportError:
    import Image

# Resize image to
size = 224, 224

infile = sys.argv[1]
outfile = sys.argv[2]

# Read an image and resize to a specific size
try:
    im = Image.open(infile)
    im.thumbnail(size, Image.ANTIALIAS)
    im.save(outfile, "JPEG")
    print("Processed " + infile + " to " + outfile)
except IOError:
    print("Cannot process image " + infile)
