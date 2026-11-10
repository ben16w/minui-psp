/*
 * pngcolor: print the average "R G B" of the centre 40% x 40% of a PNG.
 * Used by tests/device/e2e.sh to check what a screenshot of the Game Switcher shows
 * (the test fixtures are solid red / blue), without needing Python on the device.
 *
 * Usage: pngcolor <input.png>
 */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_NO_LINEAR
#define STBI_NO_HDR
#define STBI_MAX_DIMENSIONS 8192
#include "stb_image.h"

#include <stdio.h>

int main(int argc, char **argv) {
	if (argc != 2) {
		fprintf(stderr, "usage: %s <input.png>\n", argv[0]);
		return 2;
	}
	int w, h, n;
	unsigned char *px = stbi_load(argv[1], &w, &h, &n, 3);
	if (!px) {
		fprintf(stderr, "pngcolor: cannot decode %s: %s\n", argv[1], stbi_failure_reason());
		return 1;
	}
	int x0 = w * 3 / 10, x1 = w * 7 / 10, y0 = h * 3 / 10, y1 = h * 7 / 10;
	unsigned long long r = 0, g = 0, b = 0, cnt = 0;
	for (int y = y0; y < y1; y++) {
		for (int x = x0; x < x1; x++) {
			const unsigned char *p = px + ((size_t)y * w + x) * 3;
			r += p[0];
			g += p[1];
			b += p[2];
			cnt++;
		}
	}
	stbi_image_free(px);
	if (!cnt) return 1;
	printf("%llu %llu %llu\n", r / cnt, g / cnt, b / cnt);
	return 0;
}
