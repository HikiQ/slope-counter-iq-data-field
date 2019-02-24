/*
Calculates the median of an odd size array
data : array to sort (copy is sorted to keep input untouched)
reverse : if the array should be reversed for better performance
*/
function median(data, reverse) {
    // copy the array to keep the sliding window in order
    if (reverse) {
        // if we are going downhill the smallest value is always at the right end
        // reverse to get into better order
        data = data.reverse();
    } else {
        // there might be a better way to make a copy
        data = data.slice(null, null);
    }

    // sort the copy of the array
    sort(data);

    // data array is now sorted (integer division)
    return data[data.size() / 2];
}


/*
Insertion sort from
https://stackoverflow.com/a/2789530

data : array to sort in-place
*/
function sort(data) {
    var tmp = null;
    var j = null;

    // main loop traverses list from the 2nd item to the end
    for (var i = 1; i < data.size(); i++) {
        // the item to be moved is stored in tmp
        tmp = data[i];
        // traverse list starting from the index i to the 2nd item (backwards)
        // as many iterations as tmp is smaller than the item left of it
        for (j = i; j >= 1 && tmp < data[j-1]; j--) {
            // move the left side item one index to the right to make room for the
            // new smaller item
            data[j] = data[j-1];
        }
        // insert the item to a position when there is a smaller than equal on the left side
        data[j] = tmp;
    }

    // sorted in-place but return the same array to avoid returning null
    return data;
}

