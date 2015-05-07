function on_districtChange($el, elements, districts) {
    if ($el.value < 0)
        return;
    choosen_object = undefined;
    var $ptr = $("#districts"),
        keys = districts[$el.value];
    for (var i = 0; i < elements.length; ++i) {
        var $e = $("#" + elements[i]);
        $e.val('-1').html($e.find('option')[0]).trigger('refresh');
    }
    for (var i = 0; i < keys.length; ++i) {
        $ptr.append("<option value='" + keys[i][1] + "'>" + keys[i][0] + "</option>");
    }
    $ptr.trigger("refresh");
}

var choosen_object = undefined,
    err_msg = function () { alert('Ошибка получения списка. Попробуйте повторить запрос позднее или обратитесь к администратору.'); };

function request_content(base_url, skip_calc_type) {
    var calc_type = $("#calc_types").val();
    if (!choosen_object) choosen_object = { region: $("#regions").val() };
    if (!skip_calc_type)
        choosen_object['calc_type'] = calc_type;
    window.open(window.location.origin + base_url + '/cgi-bin/build?' + $.param(choosen_object), '_blank');
}

var elements_info = { regions: 'region', districts: 'district', companies: 'company', buildings: 'building', objects: 'object' };
function select_change_controller(elements, base_url, content_filter) {
    for (var el = 0; el < elements.length; ++el) {
        var $next_elem = el == elements.length - 1 ? undefined : $("#" + elements[el + 1]),
            $prev_elem = el == 0 ? undefined : $("#" + elements[el - 1]);
        $("#" + elements[el]).on('change', function ($next_elem, $prev_elem) {
            return function() {
                choosen_object = {};
                if (this.value == '-1')
                {
                    if ($prev_elem == undefined)
                        choosen_object = undefined;
                    else
                        choosen_object[elements_info[$prev_elem.attr('id')]] = $prev_elem.val();
                    if ($next_elem)
                        $next_elem.val('-1').html($next_elem.find('option')[0]).trigger('refresh');
                    return;
                }
                var this_id = elements_info[$(this).attr('id')];
                choosen_object[this_id] = this.value;
                if ($next_elem) {
                    var index = $.inArray($next_elem.attr('id'), elements);
                    if (index >= 0) {
                        for (var i = index + 1; i < elements.length; ++i) {
                            var $e = $("#" + elements[i]);
                            $e.val('-1').html($e.find('option')[0]).trigger('refresh');
                        }
                    }
                    $next_elem.val('-1').html($next_elem.find('option')[0]).trigger('refresh');
                    $.ajax({
                        method: 'get',
                        url: base_url + '/cgi-bin/' + $next_elem.attr('id'),
                        data: choosen_object,
                        success: function (data) {
                            var key = $next_elem.attr('id');
                            if (data[key]) {
                                if (content_filter)
                                    data[key] = content_filter(this_id, data[key]);
                                $.each(data[key], function (index, item) {
                                    $next_elem.append('<option value="' + item.id + '">' + item.name + '</option>');
                                });
                                $next_elem.trigger('refresh');
                            } else {
                                err_msg();
                            }
                        },
                        error: err_msg,
                    });
                }
            }}($next_elem, $prev_elem));
    }
}
