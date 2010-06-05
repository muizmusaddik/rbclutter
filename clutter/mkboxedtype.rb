#!/usr/bin/ruby

# Ruby bindings for the Clutter 'interactive canvas' library.
# Copyright (C) 2007  Neil Roberts
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA  02110-1301  USA
def rbval_to_cval(field_type, rbval)
  case field_type
  when "guint8"
    "rbclt_num_to_guint8 (#{rbval})"
  when "guint"
    "NUM2UINT (#{rbval})"
  when "gint"
    "NUM2INT (#{rbval})"
  when "gfloat"
    "NUM2DBL (#{rbval})"
  else
    raise ArgumentError, "Unknown field type #{field_type}\n"
  end
end

def cval_to_rbval(field_type, cval)
  case field_type
  when "guint8", "gint"
    "INT2NUM (#{cval})"
  when "guint"
    "UINT2NUM (#{cval})"
  when "gfloat"
    "rb_float_new (#{cval})"
  else
    raise ArgumentError, "Unknown field type #{field_type}\n"
  end
end

ARGV.each do |in_name|
  out_name = if in_name =~ /\.in\z/
               in_name[0..-4]
             else
               in_name + ".c"
             end

  in_data = File.open(in_name, "r") { |in_file| in_file.read }

  unless md = in_data.match(/\/\*\s*MAKE_BOXED\(\s*([a-zA-Z_][0-9a-zA-Z]*)
                             \s+([^\)]+)\)\s*\*\//x)
    STDERR.print("No MAKE_BOXED comment found\n")
    exit(1)
  end

  struct_name = md[1]
  struct_name_parts = struct_name.split(/(?=[A-Z])/)
  var_name = struct_name_parts[1..-1].map { |x| x.downcase }.join("_")
  data_start = md.pre_match
  data_end = md.post_match
  init_value = "0"

  fields = []

  md[2].split.each do |field|
    unless md = field.match(/\A([a-zA-Z_][0-9a-zA-Z_]*):(\S+)\z/)
      STDERR.print("Bad field: #{field}\n")
      exit(1)
    end
    if md[1] == "INIT"
      init_value = md[2]
    else
      fields << [ md[1], md[2] ]
    end
  end

  File.open(out_name, "w") do |out_file|
    out_file.print("/* Automatically generated by #{File.basename($0)}\n" \
                   "   Please edit #{File.basename(in_name)} instead of this file */\n" \
                   "\n" \
                   "#include <glib.h>\n" \
                   "#include <ruby.h>\n" \
                   "#include <rbgobject.h>\n" \
                   "#include \"rbclutter.h\"\n" \
                   "\n")

    out_file.print(data_start)

    out_file.print("static VALUE\n" \
                   "rbclt_#{var_name}_initialize (int argc, VALUE *argv, VALUE self)\n" \
                   "{\n" \
                   "  VALUE #{fields.map { |x| x[0] }.join(', ')};\n" \
                   "  #{struct_name} #{var_name};\n" \
                   "\n" \
                   "  rb_scan_args (argc, argv, \"0#{fields.size}\", " \
                   "#{fields.map { |x| '&' + x[0] }.join(', ')});\n" \
                   "\n" \
                   "  memset (&#{var_name}, #{init_value}, sizeof (#{var_name}));\n" \
                   "\n")

    fields.each do |field|
      out_file.print("  if (#{field[0]} != Qnil)\n" \
                     "    #{var_name}.#{field[0]} = #{rbval_to_cval(field[1], field[0])};\n")
    end

    out_file.print("\n" \
                   "  G_INITIALIZE (self, &#{var_name});\n" \
                   "\n" \
                   "  return Qnil;\n" \
                   "}\n" \
                   "\n")

    fields.each do |field|
      cval = "((#{struct_name} *) RVAL2BOXED (self, CLUTTER_TYPE_#{var_name.upcase}))->#{field[0]}"
      out_file.print("static VALUE\n" \
                     "rbclt_#{var_name}_#{field[0]} (VALUE self)\n" \
                     "{\n" \
                     "  return #{cval_to_rbval(field[1], cval)};\n" \
                     "}\n" \
                     "\n" \
                     "static VALUE\n" \
                     "rbclt_#{var_name}_set_#{field[0]} (VALUE self, VALUE value)\n" \
                     "{\n" \
                     "  #{cval}\n" \
                     "    = #{rbval_to_cval(field[1], 'value')};\n" \
                     "  return self;\n" \
                     "}\n" \
                     "\n")
    end

    out_file.print("static VALUE\n" \
                   "rbclt_#{var_name}_to_a (VALUE self)\n" \
                   "{\n" \
                   "  #{struct_name} *#{var_name} = " \
                   "((#{struct_name} *) RVAL2BOXED (self, CLUTTER_TYPE_#{var_name.upcase}));\n" \
                   "  return rb_ary_new3 (#{fields.size}, ")
    index = 0
    fields.each do |field|
      out_file.print("                      ") unless index == 0
      out_file.print("#{cval_to_rbval(field[1], var_name + '->' + field[0])}")
      out_file.print(",\n") unless (index += 1) >= fields.size
    end
    out_file.print(");\n" \
                   "}\n" \
                   "\n")

    unless md = data_end.match(/^\s*\/\*\s*METHOD_DEFINITIONS\s*\*\/\s*$/)
      STDERR.print("Missing METHOD_DEFINITIONS comment\n")
      exit(1)
    end

    data_start = md.pre_match
    data_end = md.post_match

    out_file.print(data_start)

    out_file.print("  rb_define_method (klass, \"initialize\", " \
                   "rbclt_#{var_name}_initialize, -1);\n")
    fields.each do |field|
      out_file.print("  rb_define_method (klass, \"#{field[0]}\", " \
                     "rbclt_#{var_name}_#{field[0]}, 0);\n" \
                     "  rb_define_method (klass, \"set_#{field[0]}\", " \
                     "rbclt_#{var_name}_set_#{field[0]}, 1);\n")
    end
    out_file.print("  rb_define_method (klass, \"to_a\", " \
                   "rbclt_#{var_name}_to_a, 0);\n")

    out_file.print(data_end)
  end
end
