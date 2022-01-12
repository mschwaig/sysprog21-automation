import (
	"list"
	"strings"
)

// this template applies for one of the 5 assignments
assignment_no: int & >0 & <=5

// every assignment except the first one are worth 100 points
#point_totals: [ 25, 100, 100, 100, 100]

// earned points fall into one of the predefined cathegories
categories: [string]: {
	// students earn between 0 and 'of' points in each category
	points: int & >=0 & <=of
	of:     int
}

// additional deductions can be made for a number of predefined radons
deductions: [string]: {
	name:        string
	description: string
	points:      int & >=0 & <=of
	of:          int
}

// tutors also provide a written explanation as freetext
comments: string
// this text must not be empty
#comments_non_whitespace_length: len(strings.TrimSpace(comments)) & >0

maximum_point_total:
	// is an int and
	int &
	// equal to the sum of point totals in all categories and
	list.Sum([ for x in categories {x.of}]) &
	// equal to the predefined total for the given assignment
	#point_totals[assignment_no-1]

point_total:
	// is an int and
	int &
	// larger than zero and
	>=0 &
	// smaller than the maximum point total and
	<=maximum_point_total &
	// equal to the points earned in all categories, but
	(list.Sum([ for x in categories {x.points}]) -
	// minus all deductions
	list.Sum([ for x in deductions {x.points}]))
