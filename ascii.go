package main

// TomatoFrames holds 8 frames of a spinning tomato.
// The calyx rotates while the round body stays put.
var TomatoFrames = []string{
	"  _/)\n (   )\n  `-'",  // 0: stem SW→NE
	"  _|)\n (   )\n  `-'",  // 1: stem right
	"   _|\n (   )\n  `-'",  // 2: stem straight up
	"  (_|\n (   )\n  `-'",  // 3: stem left
	"  (\\_\n (   )\n  `-'",  // 4: stem SE→NW
	"  (_|\n (   )\n  `-'",  // 5: stem left
	"   _|\n (   )\n  `-'",  // 6: stem straight up
	"  _|)\n (   )\n  `-'",  // 7: stem right
}

// TomatoLogo is the best single frame used as static logo on the home screen.
const TomatoLogo = "  _/)\n (   )\n  `-'"

// TomatoExplode is shown for ~1 second when a round timer fires.
const TomatoExplode = " * * * \n*(x_x)*\n * * * "

// Tagline is displayed below the logo on the home screen.
const Tagline = "Your terminal. Your rival. Your focus."
