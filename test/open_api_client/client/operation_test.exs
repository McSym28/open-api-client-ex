defmodule OpenAPIClient.Client.OperationTest do
  use ExUnit.Case, async: true
  alias OpenAPIClient.Client.Operation

  describe "parse_content_type_header/1" do
    test "successfully parses Content-Type header value" do
      assert {:ok, {"application", "json", %{}}} ==
               Operation.parse_content_type_header("application/json")
    end

    test "successfully parses Content-Type header value with whitespace for parameter list" do
      assert {:ok, {"application", "json", %{}}} ==
               Operation.parse_content_type_header("application/json; ")
    end

    test "successfully parses Content-Type header value with one parameter" do
      assert {:ok, {"text", "html", %{"charset" => "utf-8"}}} ==
               Operation.parse_content_type_header("text/html; charset=utf-8")
    end

    test "successfully parses Content-Type header value with multiple parameter" do
      assert {:ok,
              {"multipart", "form-data",
               %{"boundary" => "ExampleBoundaryString", "charset" => "koi8-u"}}} ==
               Operation.parse_content_type_header(
                 "multipart/form-data; boundary=ExampleBoundaryString; charset=koi8-u"
               )
    end

    test "failed to parse Content-Type header empty string" do
      assert {:error, :empty_string} == Operation.parse_content_type_header("")
    end

    test "failed to parse Content-Type header whitespace string" do
      assert {:error, :empty_string} == Operation.parse_content_type_header("   \t   ")
    end

    test "failed to parse Content-Type header value with missing media-type delimiter" do
      assert {:error, {:invalid_media_type_format, "application_json"}} ==
               Operation.parse_content_type_header("application_json")
    end

    test "failed to parse Content-Type header value with missing parameter delimiter" do
      assert {:error, {:invalid_parameter_format, "charset_utf-8"}} ==
               Operation.parse_content_type_header("text/html; charset_utf-8")
    end
  end
end
