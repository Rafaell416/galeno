package main

import "testing"

func TestClampReadLimitKeepsTheDefaultAndCapsTheRest(t *testing.T) {
	cases := []struct{ in, want int }{
		{0, defaultLimit}, {-5, defaultLimit}, {1, 1}, {20, 20}, {100, 100}, {101, 100}, {5000, 100},
	}
	for _, c := range cases {
		if got := clampReadLimit(c.in); got != c.want {
			t.Fatalf("clampReadLimit(%d) = %d, quería %d", c.in, got, c.want)
		}
	}
}

func TestClampContextNeverGoesNegativeOrPastTheCap(t *testing.T) {
	cases := []struct{ in, want int }{{-1, 0}, {0, 0}, {1, 1}, {5, 5}, {6, 5}, {500, 5}}
	for _, c := range cases {
		if got := clampContext(c.in); got != c.want {
			t.Fatalf("clampContext(%d) = %d, quería %d", c.in, got, c.want)
		}
	}
}
