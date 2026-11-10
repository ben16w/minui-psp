/*
 * jpg2bmp: decode a JPEG or PNG with stb_image and write it as an
 * uncompressed 24-bit BMP.
 *
 * Used by launch.sh to turn PPSSPP's save-state thumbnails (always JPEG) into
 * a file NextUI's game switcher can load: the stock TrimUI libSDL2_image is
 * built without JPEG support, while BMP is decoded by SDL itself.
 *
 * Usage: jpg2bmp <input> <output.bmp>
 */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#define STBI_NO_LINEAR
#define STBI_NO_HDR
/* Save-state thumbnails are tiny; anything bigger than this is rejected. 8192x8192 keeps
 * stride * h + 54 well below 2^32 (8192 * 3 * 8192 = 201326592). */
#define MAX_DIM 8192
#define STBI_MAX_DIMENSIONS MAX_DIM
#include "stb_image.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static void put16(unsigned char *p, uint16_t v) { p[0] = v & 0xff; p[1] = v >> 8; }
static void put32(unsigned char *p, uint32_t v) { put16(p, v & 0xffff); put16(p + 2, v >> 16); }

int main(int argc, char **argv) {
	if (argc != 3) {
		fprintf(stderr, "usage: %s <input> <output.bmp>\n", argv[0]);
		return 2;
	}

	int w, h, n;
	/* Check the size before decoding, so a huge image is rejected without allocating it. */
	if (!stbi_info(argv[1], &w, &h, &n)) {
		fprintf(stderr, "jpg2bmp: cannot read %s: %s\n", argv[1], stbi_failure_reason());
		return 1;
	}
	if (w <= 0 || h <= 0 || w > MAX_DIM || h > MAX_DIM) {
		fprintf(stderr, "jpg2bmp: %s is %dx%d, larger than %dx%d\n", argv[1], w, h, MAX_DIM, MAX_DIM);
		return 1;
	}

	unsigned char *px = stbi_load(argv[1], &w, &h, &n, 3);
	if (!px) {
		fprintf(stderr, "jpg2bmp: cannot decode %s: %s\n", argv[1], stbi_failure_reason());
		return 1;
	}
	if (w <= 0 || h <= 0 || w > MAX_DIM || h > MAX_DIM) { /* file changed since stbi_info */
		fprintf(stderr, "jpg2bmp: %s has an unsupported size\n", argv[1]);
		stbi_image_free(px);
		return 1;
	}

	/* With w, h <= MAX_DIM these cannot overflow 32 bits (the BMP header fields). */
	uint32_t stride = ((uint32_t)w * 3 + 3) & ~3u;
	uint32_t data_size = stride * (uint32_t)h;
	unsigned char hdr[54] = {0};
	hdr[0] = 'B';
	hdr[1] = 'M';
	put32(hdr + 2, 54 + data_size); /* file size */
	put32(hdr + 10, 54);            /* pixel data offset */
	put32(hdr + 14, 40);            /* BITMAPINFOHEADER */
	put32(hdr + 18, (uint32_t)w);
	put32(hdr + 22, (uint32_t)h);   /* positive height: bottom-up rows */
	put16(hdr + 26, 1);             /* planes */
	put16(hdr + 28, 24);            /* bits per pixel */
	put32(hdr + 34, data_size);

	FILE *f = fopen(argv[2], "wb");
	if (!f) {
		perror(argv[2]);
		stbi_image_free(px);
		return 1;
	}

	unsigned char *row = calloc(1, stride);
	int ok = row && fwrite(hdr, 1, sizeof(hdr), f) == sizeof(hdr);
	for (int y = h - 1; ok && y >= 0; y--) {
		const unsigned char *src = px + (size_t)y * w * 3;
		for (int x = 0; x < w; x++) {
			row[x * 3 + 0] = src[x * 3 + 2];
			row[x * 3 + 1] = src[x * 3 + 1];
			row[x * 3 + 2] = src[x * 3 + 0];
		}
		ok = fwrite(row, 1, stride, f) == stride;
	}

	free(row);
	stbi_image_free(px);
	if (fclose(f) != 0) ok = 0;
	if (!ok) {
		fprintf(stderr, "jpg2bmp: failed writing %s\n", argv[2]);
		remove(argv[2]);
		return 1;
	}
	return 0;
}
