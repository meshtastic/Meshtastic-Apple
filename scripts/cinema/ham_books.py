#
#  ham_books.py
#  Meshtastic
#
#  Copyright(c) Garth Vander Houwen 10/29/26.
#
#  The ham shack's books: made-up titles and pun authors, shared by make_textures.py, which draws
#  their spines and covers, and ham_shack.py, which shelves them. Plain data, so both can import it.

# Spines, in shelf order: title, author, cloth color, thickness and height in meters.
SPINES = [
    ("SWR: It's Fine", "Rhea Flected", (128, 30, 34), 0.045, 0.28),
    ("Antennas My HOA Can't See", "Stell Thwire", (32, 64, 112), 0.05, 0.3),
    ("73 Ways to Say Goodbye", "Seymour Signals", (34, 92, 58), 0.035, 0.25),
    ("QRP: Doing More With Less", "Milli Watts", (196, 150, 40), 0.03, 0.23),
    ("The Joy of Coax", "Bea Lun", (58, 36, 86), 0.055, 0.29),
    ("Crimpin' Ain't Easy", "Ann Derson", (190, 60, 30), 0.045, 0.27),
    ("Ferrite Beads and Other Lies", "Toro Idal", (40, 40, 44), 0.04, 0.27),
    ("Grounding for the Ungrounded", "Earl Thing", (110, 70, 34), 0.045, 0.28),
    ("Sunspots: A Waiting Game", "Sol R. Cycle", (210, 110, 30), 0.04, 0.26),
    ("Who Moved My Repeater?", "Duke Plex", (30, 96, 120), 0.035, 0.24),
    ("Morse Code in 30 Years", "Dit Dahson", (20, 20, 22), 0.05, 0.29),
    ("Propagation: Just Guess", "Ion O. Sphere", (90, 120, 40), 0.04, 0.27),
    ("The Pileup Diaries", "Kay Ulater", (150, 40, 80), 0.045, 0.28),
    ("Baluns, Ununs and Other Words", "Anne Tenna", (60, 70, 90), 0.04, 0.26),
    ("Dummy Loads for Smart People", "Watt Ever", (180, 50, 30), 0.035, 0.25),
    ("One More Antenna", "Phil Ter", (40, 100, 70), 0.06, 0.3),
    ("Explaining Ham Radio to Your Family", "Ray Dio", (70, 50, 40), 0.055, 0.29),
    ("Solder Fumes: A Love Story", "Flux Capacity", (200, 175, 120), 0.03, 0.22),
    ("Mesh Networking for Introverts", "Lora Hops", (44, 120, 80), 0.045, 0.27),
    ("Field Day: Bring Bug Spray", "Jen Erator", (120, 100, 30), 0.04, 0.26),
    ("Spurious Emissions: A Memoir", "Harmon Ics", (90, 30, 30), 0.05, 0.28),
    ("CQ CQ CQ: Is Anyone There?", "Hugh Hearmee", (30, 50, 90), 0.04, 0.25),
    ("Long Range, Long Nights", "Lora Waan", (60, 40, 100), 0.045, 0.29),
    ("The Little Book of Big Towers", "Tri Pod", (150, 140, 120), 0.025, 0.22),
    ("Ohm Sweet Ohm", "Rhea Sistor", (100, 30, 50), 0.035, 0.24),
    ("Cap A. Citor: Charged", "Cap A. Citor", (30, 80, 100), 0.04, 0.27),
    ("RF in the Shack: A Thriller", "Cy Clic", (40, 40, 40), 0.05, 0.3),
    ("Log Everything", "Rich Report", (110, 90, 60), 0.045, 0.26),
    ("Getting Your License, Again", "Vanity Callahan", (50, 90, 60), 0.035, 0.25),
    ("Interference: It Was the Fridge", "Noah Floor", (170, 120, 40), 0.045, 0.28),
    ("Tune Before You Transmit", "Max Power", (80, 30, 30), 0.04, 0.27),
]

# Covers stood face out on top of the bookcase, big enough to read from the seat: title, a line
# under it, cover color, title color.
COVERS = [
    ("SWR:\nIT'S\nFINE", "and other things we tell ourselves", (36, 52, 90), (250, 214, 90)),
    ("THE\nJOY OF\nCOAX", "fully illustrated, 50 ohm edition", (128, 30, 34), (250, 242, 225)),
    ("ONE\nMORE\nANTENNA", "a family's story", (30, 90, 60), (250, 250, 245)),
    ("CRIMPIN'\nAIN'T\nEASY", "four hundred PL-259s later", (190, 60, 30), (250, 242, 225)),
]
