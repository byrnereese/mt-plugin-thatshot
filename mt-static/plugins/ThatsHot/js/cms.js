function TopicURL() {
    document.getElementById('keyword-field').style.display = 'none';
    document.getElementById('tag-field').style.display = 'none';
    document.getElementById('url-field').style.display = 'block';
}

function TopicKeyword() {
    document.getElementById('url-field').style.display = 'none';
    document.getElementById('tag-field').style.display = 'none';
    document.getElementById('keyword-field').style.display = 'block';
}

function TopicTag() {
    document.getElementById('url-field').style.display = 'none';
    document.getElementById('keyword-field').style.display = 'none';
    document.getElementById('tag-field').style.display = 'block';
}

function StatusNow() {
    document.getElementById('date-time-fields').setAttribute('class', 'hidden');
}

function StatusSchedule() {
    document.getElementById('date-time-fields').removeAttribute('class', 'hidden');
}

function getCheckedValue(radioObj) {
    if(!radioObj)
        return "";
    var radioLength = radioObj.length;
    if(radioLength == undefined)
        if(radioObj.checked)
            return radioObj.value;
        else
            return "";
    for(var i = 0; i < radioLength; i++) {
        if(radioObj[i].checked) {
            return radioObj[i].value;
        }
    }
    return "";
}

function acceptSearchOverride() {
    document.getElementById('search-override').style.display = 'none';
    document.getElementById('keyword-blog-names').innerHTML = assembleBlogIDs();
    document.getElementById('tag-blog-names').innerHTML = assembleBlogIDs();
    showPreviewLink();
}

function hideSearchOverride() {
    // The search-override container is only included on the page if it is
    // enabled, otherwise it's excluded form the page. And, it's supposed to
    // be hidden by default. So, we need to do some special handling to keep
    // it hidden.
    try { 
        document.getElementById('search-override').style.display = 'none'; 
    }
    catch(er) {
        // Just fail silently.
    }
}

function showSearchOverride() {
    document.getElementById('search-override').style.display = 'block';
}

function assembleBlogIDs() {
    var blog_ids_array = new Array();
    var blog_obj = document.getElementById('select_blogs');
    var i;
    var count = 0;
    for (i=0; i<blog_obj.options.length; i++) {
        if (blog_obj.options[i].selected) {
            blog_ids_array[count] = blog_obj.options[i].value;
            count++;
        }
    }
    return blog_ids_array;
}

function insertTag(tagname) {
    document.getElementById('tag').value = tagname;
    document.getElementById('tag-suggestions').style.display = 'none';
    showPreviewLink();
}

function showTagSuggestions() {
    document.getElementById('tag-suggestions').style.display = 'block';
}
function hideTagSuggestions() {
    document.getElementById('tag-suggestions').style.display = 'none';
}

function toggleFile() {
    var fld = getByID("basename");
    if (fld) {
        fld.disabled = false;
        fld.focus();
        var basewarn = getByID("basename-warning");
        if (basewarn) basewarn.style.display = "block";
    }
    var img = getByID("basename-lock");
    if (img)
        img.style.display = 'none';
    return false;
}

