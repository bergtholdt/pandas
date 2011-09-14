def getFillVec(ndarray oldIndex, ndarray newIndex, dict oldMap, dict newMap,
               kind=None):

    if kind is None:
        fillVec, maskVec = getMergeVec(newIndex, oldMap)
    elif kind == 'PAD':
        fillVec, maskVec = _pad(oldIndex, newIndex, oldMap, newMap)
    elif kind == 'BACKFILL':
        fillVec, maskVec = _backfill(oldIndex, newIndex, oldMap, newMap)
    else:
        raise Exception("Don't recognize method: %s" % kind)

    return fillVec, maskVec.astype(np.bool)

@cython.wraparound(False)
def _backfill(ndarray[object] oldIndex, ndarray[object] newIndex,
              dict oldMap, dict newMap):
    '''
    Backfilling logic for generating fill vector

    Diagram of what's going on

    Old      New    Fill vector    Mask
             .        0               1
             .        0               1
             .        0               1
    A        A        0               1
             .        1               1
             .        1               1
             .        1               1
             .        1               1
             .        1               1
    B        B        1               1
             .        2               1
             .        2               1
             .        2               1
    C        C        2               1
             .                        0
             .                        0
    D
    '''
    cdef int i, j
    cdef Py_ssize_t oldLength, newLength, curLoc
    # Make empty vectors
    cdef ndarray[Py_ssize_t, ndim=1] fillVec
    cdef ndarray[int8_t, ndim=1] mask
    cdef Py_ssize_t newPos, oldPos
    cdef object prevOld, curOld

    # Get the size
    oldLength = len(oldIndex)
    newLength = len(newIndex)

    fillVec = np.empty(len(newIndex), dtype = np.intp)
    fillVec.fill(-1)

    mask = np.zeros(len(newIndex), dtype = np.int8)

    # Current positions
    oldPos = oldLength - 1
    newPos = newLength - 1

    # corner case, no filling possible
    if newIndex[0] > oldIndex[oldLength - 1]:
        return fillVec, mask

    while newPos >= 0:
        curOld = oldIndex[oldPos]

        # Until we reach a point where we are before the curOld point
        while newIndex[newPos] > curOld:
            newPos -= 1
            if newPos < 0:
                break

        # Get the location in the old index
        curLoc = oldMap[curOld]

        # At the beginning of the old index
        if oldPos == 0:
            # Make sure we are before the curOld index
            if newIndex[newPos] <= curOld:
                fillVec[:newPos + 1] = curLoc
                mask[:newPos + 1] = 1
            # Exit the main loop
            break
        else:
            # Get the index there
            prevOld = oldIndex[oldPos - 1]

            # Until we reach the previous index
            while newIndex[newPos] > prevOld:
                # Set the current fill location
                fillVec[newPos] = curLoc
                mask[newPos] = 1

                newPos -= 1
                if newPos < 0:
                    break

        # Move one period back
        oldPos -= 1

    return (fillVec, mask)

@cython.wraparound(False)
def _pad(ndarray[object] oldIndex, ndarray[object] newIndex,
         dict oldMap, dict newMap):
    '''
    Padding logic for generating fill vector

    Diagram of what's going on

    Old      New    Fill vector    Mask
             .                        0
             .                        0
             .                        0
    A        A        0               1
             .        0               1
             .        0               1
             .        0               1
             .        0               1
             .        0               1
    B        B        1               1
             .        1               1
             .        1               1
             .        1               1
    C        C        2               1
    '''
    cdef int i, j
    cdef Py_ssize_t oldLength, newLength, curLoc
    # Make empty vectors
    cdef ndarray[Py_ssize_t, ndim=1] fillVec
    cdef ndarray[int8_t, ndim=1] mask
    cdef Py_ssize_t newPos, oldPos
    cdef object prevOld, curOld

    # Get the size
    oldLength = len(oldIndex)
    newLength = len(newIndex)

    fillVec = np.empty(len(newIndex), dtype = np.intp)
    fillVec.fill(-1)

    mask = np.zeros(len(newIndex), dtype = np.int8)

    oldPos = 0
    newPos = 0

    # corner case, no filling possible
    if newIndex[newLength - 1] < oldIndex[0]:
        return fillVec, mask

    while newPos < newLength:
        curOld = oldIndex[oldPos]

        # At beginning, keep going until we go exceed the
        # first OLD index in the NEW index
        while newIndex[newPos] < curOld:
            newPos += 1
            if newPos > newLength - 1:
                break

        # We got there, get the current location in the old index
        curLoc = oldMap[curOld]

        # We're at the end of the road, need to propagate this value to the end
        if oldPos == oldLength - 1:
            if newIndex[newPos] >= curOld:
                fillVec[newPos:] = curLoc
                mask[newPos:] = 1
            break
        else:
            # Not at the end, need to go about filling

            # Get the next index so we know when to stop propagating this value
            nextOld = oldIndex[oldPos + 1]

            done = 0

            # Until we reach the next OLD value in the NEW index
            while newIndex[newPos] < nextOld:
                # Use this location to fill
                fillVec[newPos] = curLoc

                # Set mask to be 1 so will not be NaN'd
                mask[newPos] = 1
                newPos += 1

                # We got to the end of the new index
                if newPos > newLength - 1:
                    done = 1
                    break

            # We got to the end of the new index
            if done:
                break

        # We already advanced the iterold pointer to the next value,
        # inc the count
        oldPos += 1

    return fillVec, mask

def pad_inplace_float64(ndarray[float64_t] values,
                        ndarray[np.uint8_t, cast=True] mask):
    '''
    mask: True if needs to be padded otherwise False

    e.g.
    pad_inplace_float64(values, isnull(values))
    '''
    cdef:
        Py_ssize_t i, n
        float64_t val

    n = len(values)
    val = NaN
    for i from 0 <= i < n:
        if mask[i]:
            values[i] = val
        else:
            val = values[i]

def get_pad_indexer(ndarray[np.uint8_t, cast=True] mask):
    '''
    mask: True if needs to be padded otherwise False

    e.g.
    pad_inplace_float64(values, isnull(values))
    '''
    cdef:
        Py_ssize_t i, n
        Py_ssize_t idx
        ndarray[Py_ssize_t] indexer

    n = len(mask)
    indexer = np.empty(n, dtype=np.intp)

    idx = 0
    for i from 0 <= i < n:
        if not mask[i]:
            idx = i
        indexer[i] = idx

    return indexer

def get_backfill_indexer(ndarray[np.uint8_t, cast=True] mask):
    '''
    mask: True if needs to be padded otherwise False

    e.g.
    pad_inplace_float64(values, isnull(values))
    '''
    cdef:
        Py_ssize_t i, n
        Py_ssize_t idx
        ndarray[Py_ssize_t] indexer

    n = len(mask)
    indexer = np.empty(n, dtype=np.intp)

    idx = n - 1
    i = n - 1
    while i >= 0:
        if not mask[i]:
            idx = i
        indexer[i] = idx
        i -= 1

    return indexer

def backfill_inplace_float64(ndarray[float64_t] values,
                             ndarray[np.uint8_t, cast=True] mask):
    '''
    mask: True if needs to be backfilled otherwise False
    '''
    cdef:
        Py_ssize_t i, n
        float64_t val

    n = len(values)
    val = NaN
    i = n - 1
    while i >= 0:
        if mask[i]:
            values[i] = val
        else:
            val = values[i]
        i -= 1

@cython.wraparound(False)
@cython.boundscheck(False)
def getMergeVec(ndarray[object] values, dict oldMap):
    cdef Py_ssize_t i, j, length, newLength
    cdef object idx
    cdef ndarray[Py_ssize_t] fillVec
    cdef ndarray[int8_t] mask

    newLength = len(values)
    fillVec = np.empty(newLength, dtype=np.intp)
    mask = np.zeros(newLength, dtype=np.int8)
    for i from 0 <= i < newLength:
        idx = values[i]
        if idx in oldMap:
            fillVec[i] = oldMap[idx]
            mask[i] = 1

    for i from 0 <= i < newLength:
        if mask[i] == 0:
            fillVec[i] = -1

    return fillVec, mask.astype(bool)
