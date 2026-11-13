/* zero28-powerd: power button handling for PPSSPP on the MagicX Mini Zero 28.
 *
 * PPSSPP knows nothing about MinUI's sleep, so this runs beside it and does
 * what MinUI's own zero28 build does (workspace/all/common/api.c PWR_* and
 * workspace/zero28/platform/platform.c):
 *
 *   short press      sleep: stop the emulator and keymon, mute, backlight off.
 *                    The next press wakes and restores everything.
 *   hold 1 second    power off.
 *   2 min asleep     power off, unless charging.
 *
 * Unlike MinUI it doesn't blank the framebuffer: waking from a blank left
 * PPSSPP's GL output black on device (likely the display layer losing the
 * alpha mode setalpha sets at launch). The backlight alone is enough, as in
 * the N64 pak's overlay.
 *
 * On wake the backlight comes on at raw 8 and syncsettings.elf lowers it to
 * the user's level a second later. MinUI lowers it before bl_enable, and at
 * brightness 0 (raw 1) some boards then never light up.
 *
 * Power off doesn't call poweroff itself: it touches $POWEROFF_FLAG and asks
 * the emulator to quit (SIGTERM), so launch.sh can unmount the save folders
 * before it shuts down.
 *
 * usage: zero28-powerd <emulator pid>
 *   env: POWEROFF_FLAG  (default /tmp/psp_poweroff)
 *        SYSTEM_PATH    MinUI's system folder, for bl_enable/bl_disable/syncsettings.elf
 */
#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define PMIC_KEY_NAME "axp2202-pek"
#define CHARGER_ONLINE "/sys/class/power_supply/axp2202-usb/online"
#define DISP_LCD_SET_BRIGHTNESS 0x102
#define HOLD_MS 1000
#define SLEEP_POWEROFF_MS 120000

static pid_t emu_pid;
static char system_bin[512];

static long now_ms(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

static int read_int(const char *path) {
	int v = 0;
	FILE *f = fopen(path, "r");
	if (f) {
		if (fscanf(f, "%d", &v) != 1)
			v = 0;
		fclose(f);
	}
	return v;
}

static void write_int(const char *path, int v) {
	FILE *f = fopen(path, "w");
	if (f) {
		fprintf(f, "%d", v);
		fclose(f);
	}
}

static void run(const char *cmd) {
	char buf[1024];
	snprintf(buf, sizeof(buf), "%s >/dev/null 2>&1", cmd);
	if (system(buf) != 0)
		fprintf(stderr, "powerd: '%s' failed\n", cmd);
}

static void run_system_bin(const char *name) {
	char cmd[1024];
	snprintf(cmd, sizeof(cmd), "%s/%s", system_bin, name);
	run(cmd);
}

static void set_raw_brightness(int val) {
	int fd = open("/dev/disp", O_RDWR);
	if (fd < 0)
		return;
	unsigned long param[4] = {0, (unsigned long)val, 0, 0};
	ioctl(fd, DISP_LCD_SET_BRIGHTNESS, &param);
	close(fd);
}

/* The power key comes from the PMIC, not the gamepad; find its node by name. */
static int open_power_key(void) {
	DIR *dir = opendir("/sys/class/input");
	struct dirent *e;
	int fd = -1;
	if (!dir)
		return -1;
	while ((e = readdir(dir))) {
		char path[512], name[128] = {0};
		if (strncmp(e->d_name, "event", 5) != 0)
			continue;
		snprintf(path, sizeof(path), "/sys/class/input/%s/device/name", e->d_name);
		FILE *f = fopen(path, "r");
		if (!f)
			continue;
		if (fgets(name, sizeof(name), f))
			name[strcspn(name, "\n")] = 0;
		fclose(f);
		if (strcmp(name, PMIC_KEY_NAME) == 0) {
			snprintf(path, sizeof(path), "/dev/input/%s", e->d_name);
			fd = open(path, O_RDONLY | O_CLOEXEC);
			fprintf(stderr, "powerd: power key on %s\n", path);
			break;
		}
	}
	closedir(dir);
	return fd;
}

/* Waits up to timeout_ms (-1 forever) for the power key to change. Returns
 * 1 pressed, 0 released, -1 timeout, -2 error. */
static int wait_power_key(int fd, int timeout_ms) {
	long deadline = timeout_ms < 0 ? -1 : now_ms() + timeout_ms;
	for (;;) {
		int left = deadline < 0 ? 1000 : (int)(deadline - now_ms());
		if (deadline >= 0 && left <= 0)
			return -1;
		if (left > 1000)
			left = 1000;
		struct pollfd p = {fd, POLLIN, 0};
		int r = poll(&p, 1, left);
		if (kill(emu_pid, 0) != 0)
			exit(0); /* emulator gone: nothing left to manage */
		if (r < 0)
			return -2;
		if (r == 0)
			continue;
		struct input_event ev;
		if (read(fd, &ev, sizeof(ev)) != sizeof(ev))
			return -2;
		if (ev.type == EV_KEY && ev.code == KEY_POWER && ev.value != 2)
			return ev.value;
	}
}

static void request_poweroff(void) {
	const char *flag = getenv("POWEROFF_FLAG");
	fprintf(stderr, "powerd: power off\n");
	write_int(flag && *flag ? flag : "/tmp/psp_poweroff", 1);
	run("amixer sset 'DAC volume' 0");
	set_raw_brightness(0);
	run_system_bin("bl_disable");
	kill(emu_pid, SIGCONT);
	kill(emu_pid, SIGTERM);
	/* A process that ignores SIGTERM still has to go, or the device never
	 * powers off. */
	for (int i = 0; i < 50 && kill(emu_pid, 0) == 0; i++)
		usleep(100000);
	kill(emu_pid, SIGKILL);
	exit(0);
}

static void enter_sleep(void) {
	fprintf(stderr, "powerd: sleep\n");
	kill(emu_pid, SIGSTOP);
	run("killall -STOP keymon.elf");
	run("amixer sset 'DAC volume' 0");
	set_raw_brightness(0);
	run_system_bin("bl_disable");
	sync();
}

static void exit_sleep(void) {
	fprintf(stderr, "powerd: wake\n");
	run("killall -CONT keymon.elf");
	set_raw_brightness(8); /* MinUI: fixes the screen staying off on some boards */
	run_system_bin("bl_enable");
	run("setalpha 0"); /* in case the display layer lost its alpha mode anyway */
	run_system_bin("syncsettings.elf"); /* the user's brightness and volume */
	kill(emu_pid, SIGCONT);
}

int main(int argc, char **argv) {
	if (argc < 2 || (emu_pid = (pid_t)atoi(argv[1])) <= 0) {
		fprintf(stderr, "usage: %s <emulator pid>\n", argv[0]);
		return 1;
	}
	const char *sp = getenv("SYSTEM_PATH");
	snprintf(system_bin, sizeof(system_bin), "%s/bin", sp && *sp ? sp : "/mnt/SDCARD/.system/zero28");

	int fd = open_power_key();
	if (fd < 0) {
		fprintf(stderr, "powerd: no %s input device\n", PMIC_KEY_NAME);
		return 1;
	}

	for (;;) {
		if (wait_power_key(fd, -1) != 1)
			continue;
		/* Pressed while awake: a hold powers off, a tap sleeps. */
		if (wait_power_key(fd, HOLD_MS) == -1)
			request_poweroff();

		enter_sleep();
		long slept_at = now_ms();
		for (;;) {
			int r = wait_power_key(fd, 5000);
			if (r == 1) {
				/* Wake on release, so the release doesn't start another sleep. */
				while (wait_power_key(fd, -1) != 0)
					;
				break;
			}
			if (r == -1 && now_ms() - slept_at >= SLEEP_POWEROFF_MS) {
				if (read_int(CHARGER_ONLINE))
					slept_at += 60000; /* check again in a minute, as MinUI does */
				else
					request_poweroff();
			}
		}
		exit_sleep();
	}
}
